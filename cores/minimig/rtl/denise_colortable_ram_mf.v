// SPDX-License-Identifier: GPL-3.0-or-later
// denise_colortable_ram_mf.v (Retro25) — Ersatz für das altsyncram-Original
//
// Zweck: AGA-Farbtabelle (256 x 32 bit), je ein Schreib- und ein Leseport, mit
//   denselben Ports wie MiSTers Datei, aber inferiert. Byte-Freigaben zerlegt
//   Quartus Pro sonst je Byte (docs/core-portieren.md).
// Takt: clock für beide Ports; enable (clocken) wirkt auf Schreiben und Lesen.
// Schnittstelle: Lesedaten einen Takt nach rdaddress; beim Lesen während des
//   Schreibens derselben Adresse kommen die alten Daten (wie OLD_DATA im
//   Original).
// Bytefreigaben: Denise schreibt nur 4'b0011 (LOCT, untere Hälfte) oder 4'b1111.
//   Darum genügen zwei 16-bit-Bänke: byteena_a[0] schaltet die untere, [2] die
//   obere Hälfte; [1] und [3] bleiben unbenutzt. So belegt die Tabelle zwei
//   statt vier M20K-Blöcke.
// Testbench: tb/tb_minimig_ram.v (Questa)
module denise_colortable_ram_mf
(
	input  wire [3:0]  byteena_a,
	input  wire        clock,
	input  wire [31:0] data,
	input  wire        enable,
	input  wire [7:0]  rdaddress,
	input  wire [7:0]  wraddress,
	input  wire        wren,
	output reg  [31:0] q
);

(* ramstyle = "M20K" *) reg [15:0] ram_lo [0:255];
(* ramstyle = "M20K" *) reg [15:0] ram_hi [0:255];

always @(posedge clock) begin
	if (enable) begin
		if (wren && byteena_a[0]) ram_lo[wraddress] <= data[15:0];
		q[15:0] <= ram_lo[rdaddress];
	end
end

always @(posedge clock) begin
	if (enable) begin
		if (wren && byteena_a[2]) ram_hi[wraddress] <= data[31:16];
		q[31:16] <= ram_hi[rdaddress];
	end
end

endmodule
