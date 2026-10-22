// SPDX-License-Identifier: GPL-3.0-or-later
// p0_regs — Testregister für P0 an einer exportierten Avalon-Brücke.
//
// Zweck:  Linux soll nach jedem Core-Wechsel prüfen können, welcher Core
//         geladen ist und ob die Brücke noch Daten in beide Richtungen
//         trägt. Wie ein Namensschild an der Tür plus ein Notizzettel:
//         Das Schild (ID) verrät, wer drin wohnt; auf den Zettel (SCRATCH)
//         schreibt man etwas und liest nach, ob es noch dasteht.
// Takt:   clk (Takt der Brücke, 100 MHz), synchroner Reset rst (aktiv high).
// Ports:  Avalon-MM-Slave, 32 Bit, Wortadresse avs_address. Immer bereit
//         (avs_waitrequest = 0); Lesedaten einen Takt nach avs_read gültig
//         (avs_readdatavalid). status wird ungefiltert durchgereicht.
// Register (Byte-Offset):
//         0x0 ID      nur lesen, Parameter ID
//         0x4 SCRATCH lesen/schreiben, byteweise (avs_byteenable)
//         0x8 UPTIME  nur lesen, Takte seit dem Reset (läuft über)
//         0xC STATUS  nur lesen, Eingang status

`default_nettype none

module p0_regs #(
    parameter [31:0] ID = 32'h5232_3541   // "R25A"
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [1:0]  avs_address,
    input  wire        avs_write,
    input  wire [31:0] avs_writedata,
    input  wire [3:0]  avs_byteenable,
    input  wire        avs_read,
    output reg  [31:0] avs_readdata,
    output reg         avs_readdatavalid,
    output wire        avs_waitrequest,
    input  wire [31:0] status
);

    reg [31:0] scratch_q;
    reg [31:0] uptime_q;

    assign avs_waitrequest = 1'b0;

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            scratch_q         <= 32'd0;
            uptime_q          <= 32'd0;
            avs_readdata      <= 32'd0;
            avs_readdatavalid <= 1'b0;
        end else begin
            uptime_q <= uptime_q + 32'd1;

            if (avs_write && avs_address == 2'd1) begin
                for (i = 0; i < 4; i = i + 1)
                    if (avs_byteenable[i])
                        scratch_q[8*i +: 8] <= avs_writedata[8*i +: 8];
            end

            avs_readdatavalid <= avs_read;
            if (avs_read) begin
                case (avs_address)
                    2'd0:    avs_readdata <= ID;
                    2'd1:    avs_readdata <= scratch_q;
                    2'd2:    avs_readdata <= uptime_q;
                    default: avs_readdata <= status;
                endcase
            end
        end
    end

endmodule

`default_nettype wire
