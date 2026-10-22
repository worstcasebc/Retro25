// SPDX-License-Identifier: GPL-3.0-or-later
// opl3_mem — Programm- und Datenspeicher der OPL3-Emulation für Agilex 5
// (Retro25).
//
// Ersatz für MiSTers opl3_mem (rtl/opl3/opl3fm.sv), gleiche Schnittstelle:
// Port 1 liest/schreibt Bytes (Z80, 8K x 8), Port 2 16-bit-Wörter
// (Sequenzer, 4K x 16); Wort w = {Byte 2w+1, Byte 2w}. Ein Takt für beide.
//
// Warum neu: MiSTer beschreibt einen Speicher mit zwei Portbreiten, in den
// beide Ports schreiben. Agilex 5 kann das nicht (nur gleiche Breiten) —
// Quartus baute ihn aus 65 000 Registern. Hier zwei Bänke 4K x 8 (gerade und
// ungerade Bytes), je ein Zwei-Port-Speicher gleicher Breite (zusammen 4 M20K):
// Port 1 greift auf eine Bank zu, Port 2 auf beide.
//
// Nur RATIO = 2 (DATA_WIDTH2 = 2 * DATA_WIDTH1), wie im C64-Core benutzt.
// Zeitverhalten wie im Original: Daten einen Takt nach der Adresse. Lesen und
// Schreiben derselben Adresse im selben Takt ist nicht festgelegt (no_rw_check).
// Gleichzeitiges Schreiben beider Ports in dasselbe Byte ist nicht definiert.

module opl3_mem
#(
	parameter DATA_WIDTH1    = 8,
	parameter ADDRESS_WIDTH1 = 13,
	parameter ADDRESS_WIDTH2 = 12,
	parameter INIT_FILE      = "opl3prg.mem"
)
(
	input                         clk,
	input                         we1,
	input    [ADDRESS_WIDTH1-1:0] addr1,
	input       [DATA_WIDTH1-1:0] data_in1,
	output      [DATA_WIDTH1-1:0] data_out1,

	input                         we2,
	input    [ADDRESS_WIDTH2-1:0] addr2,
	input     [2*DATA_WIDTH1-1:0] data_in2,
	output    [2*DATA_WIDTH1-1:0] data_out2
);

localparam DW    = DATA_WIDTH1;
localparam DEPTH = 1 << ADDRESS_WIDTH2;

// no_rw_check: Agilex 5 kann im Zwei-Port-Betrieb das Lesen beim
// gleichzeitigen Schreiben derselben Adresse nicht festlegen — ohne das
// Attribut baut Quartus Register (Info 276009). Lesen und Schreiben derselben
// Adresse im selben Takt liefert dann einen beliebigen Wert (im Original ein
// Wettlauf zweier always-Blöcke; Z80 und Sequenzer tun das nicht).
(* ramstyle = "no_rw_check" *) reg [DW-1:0] mem_lo[0:DEPTH-1];   // gerade Bytes
(* ramstyle = "no_rw_check" *) reg [DW-1:0] mem_hi[0:DEPTH-1];   // ungerade Bytes

// Inhalt aus der Datei des Originals (16-bit-Wörter) auf die Bänke verteilen
reg [2*DW-1:0] init_words[0:DEPTH-1];
integer i;
initial begin
	$readmemh(INIT_FILE, init_words);
	for (i = 0; i < DEPTH; i = i + 1) begin
		mem_lo[i] = init_words[i][DW-1:0];
		mem_hi[i] = init_words[i][2*DW-1:DW];
	end
end

wire [ADDRESS_WIDTH2-1:0] w1 = addr1[ADDRESS_WIDTH1-1:1];
wire                      odd1 = addr1[0];

reg [DW-1:0] lo_q1, hi_q1, lo_q2, hi_q2;
reg          odd1_q;

// Bank gerade: Port 1 und Port 2
always @(posedge clk) begin
	if (we1 && !odd1) mem_lo[w1] <= data_in1;
	lo_q1 <= mem_lo[w1];
end
always @(posedge clk) begin
	if (we2) mem_lo[addr2] <= data_in2[DW-1:0];
	lo_q2 <= mem_lo[addr2];
end

// Bank ungerade: Port 1 und Port 2
always @(posedge clk) begin
	if (we1 && odd1) mem_hi[w1] <= data_in1;
	hi_q1 <= mem_hi[w1];
end
always @(posedge clk) begin
	if (we2) mem_hi[addr2] <= data_in2[2*DW-1:DW];
	hi_q2 <= mem_hi[addr2];
end

always @(posedge clk) odd1_q <= odd1;

assign data_out1 = odd1_q ? hi_q1 : lo_q1;
assign data_out2 = {hi_q2, lo_q2};

endmodule
