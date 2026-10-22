// SPDX-License-Identifier: GPL-3.0-or-later
// hps_gp_bridge — Ersatz für die GPO/GPI-Register des Cyclone-V-HPS.
//
// Zweck:  MiSTers Linux-Programm (Main_MiSTer) spricht mit dem Core über zwei
//         32-Bit-Register: gp_out (HPS -> FPGA) und gp_in (FPGA -> HPS). Beim
//         Cyclone V stecken sie im HPS (cyclonev_hps_interface_mpu_general_
//         purpose); der Agilex 5 hat sie nicht. Dieses Modul bildet sie als
//         Register an der Lightweight-Bridge nach, sodass sys_top und hps_io
//         unverändert bleiben.
//         Analogie: zwei Briefkästen. In gp_out wirft Linux Briefe ein, das
//         Fähnchen (Bit 17, Strobe) zeigt „neuer Brief“. sys_top schaut im Takt
//         des Cores (clk_sys) nach. Damit kein Brief übersehen wird, gibt dieser
//         Briefkasten einen neuen Brief erst frei, wenn der Core den vorigen
//         gesehen hat — beim Cyclone V war Linux langsam genug, die A76-Kerne
//         des Agilex sind es nicht.
// Takte:  clk_av (Brücke, 100 MHz) mit synchronem Reset rst_av (aktiv high);
//         clk_sys (Takt des Cores aus HPS_BUS[36], beliebig, kann fehlen).
//         Übergänge: Handshake per Toggle (req/ack, je 2 FF), gp_in per 2 FF
//         je Bit (Main liest gp_in nur, wenn die Daten stillstehen), gp_out
//         geht als stabiles Register an sys_top, das es selbst synchronisiert.
// Ports:  Avalon-MM-Slave, 32 Bit, Wortadresse avs_address:
//           0x00 GPO     lesen/schreiben (byteweise). Ein Schreibzugriff endet
//                        (waitrequest = 0) erst, wenn clk_sys den neuen Wert
//                        übernommen hat; spätestens nach TIMEOUT Takten oder
//                        sobald clk_sys als stehend erkannt ist.
//           0x04 GPI     nur lesen: gp_in, synchronisiert. Läuft clk_sys nicht,
//                        liest es 0x8000_0000 (Bit 31 = 1: „FPGA nicht bereit“,
//                        so wertet Main_MiSTer es aus).
//           0x08 STATUS  Bit 0 = clk_sys läuft; Bit 1 = mindestens ein
//                        Schreibzugriff lief in die Zeitgrenze (bleibt stehen,
//                        Schreiben einer 1 auf Bit 1 löscht es)
//           0x0C ID      nur lesen, 0x5232_3547 („R25G“)
//         gp_out — an sys_top (statt des Cyclone-V-Atoms), Takt clk_av.
//         gp_in  — von sys_top, Takt clk_sys (dort schon mit der Kennung
//                  0x5CA623 gemultiplext, wie im Original).
// Zeiten: TIMEOUT Takte clk_av (Default 20 µs), ALIVE_WINDOW Takte clk_av ohne
//         Lebenszeichen von clk_sys, nach denen er als stehend gilt
//         (Default 10 µs, also clk_sys unter ~100 kHz = steht).

`default_nettype none

module hps_gp_bridge #(
    parameter TIMEOUT      = 2000,
    parameter ALIVE_WINDOW = 1000
) (
    input  wire        clk_av,
    input  wire        rst_av,
    input  wire [1:0]  avs_address,
    input  wire        avs_write,
    input  wire [31:0] avs_writedata,
    input  wire [3:0]  avs_byteenable,
    input  wire        avs_read,
    output reg  [31:0] avs_readdata,
    output reg         avs_readdatavalid,
    output wire        avs_waitrequest,

    input  wire        clk_sys,
    output wire [31:0] gp_out,
    input  wire [31:0] gp_in
);

    localparam [31:0] BRIDGE_ID = 32'h5232_3547;   // "R25G"

    // ---------------------------------------------------------------------
    // Seite clk_sys: Handshake quittieren, Lebenszeichen erzeugen
    // ---------------------------------------------------------------------
    // Startwerte: Das FPGA lädt Register mit 0, die Simulation braucht sie
    // ausdrücklich (clk_sys hat keinen Reset — er läuft vielleicht gar nicht).
    reg req_toggle_q = 1'b0;     // clk_av: wechselt bei jedem neuen GPO-Wert
    reg req_meta_q = 1'b0, req_sys_q = 1'b0;   // clk_sys: 2-FF-Synchronizer
    reg ack_toggle_q = 1'b0;     // clk_sys: Quittung
    reg alive_toggle_q = 1'b0;   // clk_sys: wechselt jeden Takt

    always @(posedge clk_sys) begin
        req_meta_q     <= req_toggle_q;
        req_sys_q      <= req_meta_q;
        ack_toggle_q   <= req_sys_q;
        alive_toggle_q <= ~alive_toggle_q;
    end

    // ---------------------------------------------------------------------
    // Seite clk_av: Synchronizer
    // ---------------------------------------------------------------------
    reg        ack_meta_q = 1'b0, ack_av_q = 1'b0;
    reg        alive_meta_q, alive_av_q, alive_prev_q;
    reg [31:0] gpi_meta_q,   gpi_av_q;

    always @(posedge clk_av) begin
        ack_meta_q   <= ack_toggle_q;
        ack_av_q     <= ack_meta_q;
        alive_meta_q <= alive_toggle_q;
        alive_av_q   <= alive_meta_q;
        alive_prev_q <= alive_av_q;
        gpi_meta_q   <= gp_in;
        gpi_av_q     <= gpi_meta_q;
    end

    // clk_sys gilt als laufend, solange sein Lebenszeichen innerhalb von
    // ALIVE_WINDOW Takten wechselt.
    reg [$clog2(ALIVE_WINDOW+1)-1:0] quiet_q;
    wire sys_alive = (quiet_q < ALIVE_WINDOW);

    always @(posedge clk_av) begin
        if (rst_av)
            quiet_q <= ALIVE_WINDOW;            // erst nach einem Wechsel „läuft“
        else if (alive_av_q != alive_prev_q)
            quiet_q <= 0;
        else if (quiet_q < ALIVE_WINDOW)
            quiet_q <= quiet_q + 1'b1;
    end

    // ---------------------------------------------------------------------
    // Seite clk_av: Register und Schreib-Handshake
    // ---------------------------------------------------------------------
    localparam S_IDLE = 2'd0, S_WAIT = 2'd1, S_DONE = 2'd2;

    reg [1:0]  state_q;
    reg [31:0] gpo_q;
    reg [$clog2(TIMEOUT+1)-1:0] timer_q;
    reg        timeout_flag_q;

    assign gp_out = gpo_q;

    wire gpo_write = avs_write && (avs_address == 2'd0);

    // Ein GPO-Schreibzugriff wird angehalten, bis S_DONE erreicht ist; alle
    // anderen Zugriffe enden sofort.
    assign avs_waitrequest = gpo_write && (state_q != S_DONE);

    integer i;
    reg [31:0] gpo_new;

    always @(*) begin
        gpo_new = gpo_q;
        for (i = 0; i < 4; i = i + 1)
            if (avs_byteenable[i])
                gpo_new[8*i +: 8] = avs_writedata[8*i +: 8];
    end

    always @(posedge clk_av) begin
        if (rst_av) begin
            state_q        <= S_IDLE;
            gpo_q          <= 32'd0;
            req_toggle_q   <= 1'b0;
            timer_q        <= 0;
            timeout_flag_q <= 1'b0;
        end else begin
            case (state_q)
                S_IDLE:
                    if (gpo_write) begin
                        gpo_q <= gpo_new;
                        if (sys_alive) begin
                            req_toggle_q <= ~req_toggle_q;
                            timer_q      <= 0;
                            state_q      <= S_WAIT;
                        end else begin
                            state_q <= S_DONE;      // niemand da, der quittiert
                        end
                    end
                S_WAIT:
                    if (ack_av_q == req_toggle_q) begin
                        state_q <= S_DONE;
                    end else if (timer_q == TIMEOUT || !sys_alive) begin
                        timeout_flag_q <= 1'b1;
                        state_q        <= S_DONE;
                    end else begin
                        timer_q <= timer_q + 1'b1;
                    end
                default:                        // S_DONE: Zugriff endet jetzt
                    state_q <= S_IDLE;
            endcase

            if (avs_write && avs_address == 2'd2 && avs_byteenable[0] && avs_writedata[1])
                timeout_flag_q <= 1'b0;
        end
    end

    // ---------------------------------------------------------------------
    // Lesen
    // ---------------------------------------------------------------------
    always @(posedge clk_av) begin
        if (rst_av) begin
            avs_readdata      <= 32'd0;
            avs_readdatavalid <= 1'b0;
        end else begin
            avs_readdatavalid <= avs_read;
            if (avs_read) begin
                case (avs_address)
                    2'd0:    avs_readdata <= gpo_q;
                    2'd1:    avs_readdata <= sys_alive ? gpi_av_q : 32'h8000_0000;
                    2'd2:    avs_readdata <= {30'd0, timeout_flag_q, sys_alive};
                    default: avs_readdata <= BRIDGE_ID;
                endcase
            end
        end
    end

endmodule

`default_nettype wire
