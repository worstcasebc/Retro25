// SPDX-License-Identifier: GPL-3.0-or-later
// Übernommen aus C64-DE25 (gleicher Autor).
// i2c_write — schreibt ein Register eines I2C-Bausteins (nur Schreiben).
//
// Zweck:  I2C ist ein Zweidraht-Bus: SCL gibt den Takt, auf SDA wandern die
//         Bits. Beide Leitungen hängen über Widerstände an 3,3 V; jeder
//         Teilnehmer kann sie nur auf 0 ziehen oder loslassen (wie eine
//         Notbremse, an der jeder ziehen darf). Eine Übertragung:
//           Start, Bausteinadresse, Registeradresse, Datenbyte, Stopp
//         Nach jedem Byte lässt der Sender SDA für ein Bit los; der Baustein
//         zieht sie zur Bestätigung auf 0 (ACK).
// Takt:   clk, synchroner Reset rst (aktiv high). Ein SCL-Takt dauert
//         4 * CLKS_PER_QUARTER Takte (Default 50 MHz / 500 = 100 kHz).
// Ports:  start = 1 für einen Takt (nur wenn busy = 0) überträgt
//         dev_addr (8 Bit, unterstes Bit 0 = Schreiben), reg_addr, data.
//         done_q = 1 für einen Takt am Ende; ack_error_q = 1 heißt,
//         mindestens ein Byte wurde nicht bestätigt.
//         scl_oe_q/sda_oe_q = 1: Leitung auf 0 ziehen; 0: loslassen. Das
//         Top-Level macht daraus Tri-State-Pins. sda_in ist der Pegel am Pin.
// Vereinfachung: Der Baustein darf SCL nicht festhalten (kein Clock
//         Stretching), und es gibt nur einen Sender am Bus.

`default_nettype none

module i2c_write #(
    parameter CLKS_PER_QUARTER = 125
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [7:0] dev_addr,
    input  wire [7:0] reg_addr,
    input  wire [7:0] data,
    output wire       busy,
    output reg        done_q,
    output reg        ack_error_q,
    output reg        scl_oe_q,
    output reg        sda_oe_q,
    input  wire       sda_in
);

    localparam DIV_W = (CLKS_PER_QUARTER > 1) ? $clog2(CLKS_PER_QUARTER) : 1;

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_BIT   = 2'd2,
                     S_STOP  = 2'd3;

    // SDA kommt von außen und ist nicht zum Takt synchron.
    wire sda_sync_q;

    sync_2ff u_sync_sda (
        .clk      (clk),
        .d_async  (sda_in),
        .d_sync_q (sda_sync_q)
    );

    reg [1:0]       state_q;
    reg [1:0]       phase_q;    // Viertel des aktuellen SCL-Takts
    reg [4:0]       bit_q;      // 0..26: drei Bytes zu je 8 Bit + ACK-Bit
    reg [26:0]      shift_q;    // nächstes Bit steht oben
    reg [DIV_W-1:0] div_q;

    wire tick    = (div_q == CLKS_PER_QUARTER - 1);
    wire ack_bit = (bit_q == 5'd8) || (bit_q == 5'd17) || (bit_q == 5'd26);

    assign busy = (state_q != S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state_q     <= S_IDLE;
            phase_q     <= 2'd0;
            bit_q       <= 5'd0;
            div_q       <= {DIV_W{1'b0}};
            done_q      <= 1'b0;
            ack_error_q <= 1'b0;
            scl_oe_q    <= 1'b0;
            sda_oe_q    <= 1'b0;
        end else begin
            done_q <= 1'b0;
            div_q  <= (busy && !tick) ? div_q + 1'b1 : {DIV_W{1'b0}};

            case (state_q)
                S_IDLE: begin
                    if (start) begin
                        // In den ACK-Bits steht eine 1: SDA loslassen.
                        shift_q     <= {dev_addr, 1'b1, reg_addr, 1'b1, data, 1'b1};
                        ack_error_q <= 1'b0;
                        sda_oe_q    <= 1'b1;    // Start: SDA fällt, SCL ist 1
                        phase_q     <= 2'd0;
                        state_q     <= S_START;
                    end
                end

                S_START: if (tick) begin
                    if (phase_q == 2'd0) begin
                        scl_oe_q <= 1'b1;
                        phase_q  <= 2'd1;
                    end else begin
                        sda_oe_q <= ~shift_q[26];
                        bit_q    <= 5'd0;
                        phase_q  <= 2'd0;
                        state_q  <= S_BIT;
                    end
                end

                // Ein Bit: SCL 0 (SDA liegt an) - SCL 1 - SCL 1 - SCL 0.
                // SDA ändert sich nur, während SCL 0 ist.
                S_BIT: if (tick) begin
                    phase_q <= phase_q + 1'b1;
                    case (phase_q)
                        2'd0: scl_oe_q <= 1'b0;
                        2'd1: if (ack_bit && sda_sync_q) ack_error_q <= 1'b1;
                        2'd2: scl_oe_q <= 1'b1;
                        2'd3: begin
                            if (bit_q == 5'd26) begin
                                sda_oe_q <= 1'b1;
                                state_q  <= S_STOP;
                            end else begin
                                sda_oe_q <= ~shift_q[25];
                                shift_q  <= {shift_q[25:0], 1'b1};
                                bit_q    <= bit_q + 1'b1;
                            end
                        end
                    endcase
                end

                // Stopp: SDA steigt, während SCL 1 ist.
                S_STOP: if (tick) begin
                    phase_q <= phase_q + 1'b1;
                    case (phase_q)
                        2'd0: scl_oe_q <= 1'b0;
                        2'd1: sda_oe_q <= 1'b0;
                        default: begin
                            done_q  <= 1'b1;
                            state_q <= S_IDLE;
                        end
                    endcase
                end
            endcase
        end
    end

endmodule

`default_nettype wire
