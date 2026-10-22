// SPDX-License-Identifier: GPL-3.0-or-later
// Übernommen aus C64-DE25 (gleicher Autor).
// hdmi_config — konfiguriert den HDMI-Sender ADV7513 über I2C.
//
// Zweck:  Der ADV7513 ist nach dem Einschalten im Schlafmodus. Erst nach
//         einer Reihe von Registerzugriffen gibt er das parallele Video
//         (RGB, HS, VS, DE) als HDMI aus. Dieses Modul schreibt die Register
//         der Reihe nach und wiederholt einen Zugriff, bis der Baustein ihn
//         bestätigt. Die Registerwerte stammen aus Terasics Demo HDMI_TX
//         (I2C_HDMI_Config.v) für das DE25-Nano — mit einer Ergänzung:
//         Register $0A = $00 sagt dem Baustein, dass der Tontakt MCLK das
//         128-Fache der Abtastrate ist (Terasic liefert das 256-Fache, die
//         Voreinstellung). Der Ton kommt als I2S mit 16 Bit; siehe i2s_tx.
//         Zweite Abweichung: Der Audio-Infoframe meldet 2 Kanäle ($73 = $01,
//         $76 = $00). Terasic meldet dort 8 Kanäle ($07, $1F), obwohl nur
//         Stereo gesendet wird; ein Monitor stört sich daran nicht, ein
//         Mehrkanal-Empfänger kann deshalb stumm bleiben.
//         Zieht der Baustein seine Interrupt-Leitung auf 0 (z. B. Monitor
//         neu eingesteckt — dabei fällt er in den Schlafmodus zurück), wird
//         die Konfiguration wiederholt.
// Takt:   clk, synchroner Reset rst (aktiv high).
// Ports:  int_n — Interrupt des ADV7513, low-aktiv, asynchron.
//         scl_oe_q/sda_oe_q/sda_in — I2C-Bus, siehe i2c_write.
//         ready_q = 1: alle Register geschrieben.
//         nack_q  = 1: der letzte Zugriff wurde nicht bestätigt (Debug).
// Parameter: STARTUP_CLKS — Wartezeit nach Reset, bevor der erste Zugriff
//         beginnt (Default 0,2 s bei 50 MHz).

`default_nettype none

module hdmi_config #(
    parameter CLKS_PER_QUARTER = 125,
    parameter STARTUP_CLKS     = 10_000_000
) (
    input  wire clk,
    input  wire rst,
    input  wire int_n,
    output wire scl_oe_q,
    output wire sda_oe_q,
    input  wire sda_in,
    output reg  ready_q,
    output reg  nack_q
);

    localparam [7:0] DEV_ADDR = 8'h72;
    localparam       N_REGS   = 34;
    localparam       WAIT_W   = (STARTUP_CLKS > 1) ? $clog2(STARTUP_CLKS) : 1;

    // {Registeradresse, Wert}
    function [15:0] reg_entry(input [5:0] index);
        case (index)
            6'd0:    reg_entry = 16'h9803;  // Pflichtwert laut Hersteller
            6'd1:    reg_entry = 16'h0100;  // Audio: N = 6144 (48 kHz)
            6'd2:    reg_entry = 16'h0218;
            6'd3:    reg_entry = 16'h0300;
            6'd4:    reg_entry = 16'h0A00;  // Audio: I2S, MCLK = 128 x Abtastrate
            6'd5:    reg_entry = 16'h0B2E;  // Audio: MCLK aktiv
            6'd6:    reg_entry = 16'h0CBC;  // Audio: I2S
            6'd7:    reg_entry = 16'h1472;  // Audio: 16 Bit
            6'd8:    reg_entry = 16'h1520;  // Eingang RGB 4:4:4, getrennte Syncs
            6'd9:    reg_entry = 16'h1630;  // Ausgang 4:4:4, 24 Bit
            6'd10:   reg_entry = 16'h1846;  // keine Farbraumumrechnung
            6'd11:   reg_entry = 16'h4080;  // General-Control-Paket ein
            6'd12:   reg_entry = 16'h4110;  // Schlafmodus aus
            6'd13:   reg_entry = 16'h49A8;  // Dither-Einstellung
            6'd14:   reg_entry = 16'h5510;  // AVI-Infoframe: RGB
            6'd15:   reg_entry = 16'h5608;  // AVI-Infoframe: Seitenverhältnis
            6'd16:   reg_entry = 16'h96F6;  // Interrupts quittieren
            6'd17:   reg_entry = 16'h7301;  // Audio-Infoframe: 2 Kanäle
            6'd18:   reg_entry = 16'h7600;  // Audio-Infoframe: Lautsprecher vorn links/rechts
            6'd19:   reg_entry = 16'h9803;  // ab hier Pflichtwerte laut Hersteller
            6'd20:   reg_entry = 16'h9902;
            6'd21:   reg_entry = 16'h9AE0;
            6'd22:   reg_entry = 16'h9C30;
            6'd23:   reg_entry = 16'h9D61;
            6'd24:   reg_entry = 16'hA2A4;
            6'd25:   reg_entry = 16'hA3A4;
            6'd26:   reg_entry = 16'hA504;
            6'd27:   reg_entry = 16'hAB40;
            6'd28:   reg_entry = 16'hAF16;  // HDMI-Modus (statt DVI)
            6'd29:   reg_entry = 16'hBA60;  // keine Taktverzögerung
            6'd30:   reg_entry = 16'hD1FF;
            6'd31:   reg_entry = 16'hDE10;
            6'd32:   reg_entry = 16'hE460;
            6'd33:   reg_entry = 16'hFA7D;
            default: reg_entry = 16'h9803;
        endcase
    endfunction

    localparam [1:0] S_WAIT  = 2'd0,
                     S_START = 2'd1,
                     S_BUSY  = 2'd2,
                     S_READY = 2'd3;

    wire int_n_sync_q;

    sync_2ff u_sync_int (
        .clk      (clk),
        .d_async  (int_n),
        .d_sync_q (int_n_sync_q)
    );

    reg [1:0]        state_q;
    reg [5:0]        index_q;
    reg [WAIT_W-1:0] wait_q;

    wire [15:0] entry = reg_entry(index_q);
    wire        i2c_done;
    wire        i2c_ack_error;
    wire        i2c_busy;

    i2c_write #(.CLKS_PER_QUARTER(CLKS_PER_QUARTER)) u_i2c_write (
        .clk         (clk),
        .rst         (rst),
        .start       (state_q == S_START),
        .dev_addr    (DEV_ADDR),
        .reg_addr    (entry[15:8]),
        .data        (entry[7:0]),
        .busy        (i2c_busy),
        .done_q      (i2c_done),
        .ack_error_q (i2c_ack_error),
        .scl_oe_q    (scl_oe_q),
        .sda_oe_q    (sda_oe_q),
        .sda_in      (sda_in)
    );

    always @(posedge clk) begin
        if (rst) begin
            state_q <= S_WAIT;
            index_q <= 6'd0;
            wait_q  <= {WAIT_W{1'b0}};
            ready_q <= 1'b0;
            nack_q  <= 1'b0;
        end else begin
            case (state_q)
                S_WAIT: begin
                    if (wait_q == STARTUP_CLKS - 1) state_q <= S_START;
                    else                            wait_q  <= wait_q + 1'b1;
                end

                S_START: state_q <= S_BUSY;

                S_BUSY: if (i2c_done) begin
                    nack_q <= i2c_ack_error;
                    if (i2c_ack_error) begin
                        state_q <= S_START;             // gleichen Zugriff wiederholen
                    end else if (index_q == N_REGS - 1) begin
                        ready_q <= 1'b1;
                        state_q <= S_READY;
                    end else begin
                        index_q <= index_q + 1'b1;
                        state_q <= S_START;
                    end
                end

                S_READY: if (!int_n_sync_q) begin
                    ready_q <= 1'b0;
                    index_q <= 6'd0;
                    state_q <= S_START;
                end
            endcase
        end
    end

    // i2c_busy wird hier nicht gebraucht: Der Ablauf wartet auf i2c_done.
    wire unused = i2c_busy;

endmodule

`default_nettype wire
