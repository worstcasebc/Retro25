// SPDX-License-Identifier: GPL-3.0-or-later
// Simulator: Questa
// Dateien: cores/megadrive/rtl/vram_ip.v
// Bibliotheken: altera_lnsim
//
// tb_md_vram_ip — prüft den VRAM-Ersatz (altera_syncram, 256 x 256 bit):
//  einzelne Bytes schreiben wie vram.v (genau eine Byte-Freigabe, Byte =
//  Adresse[4:0]), ganzes Wort lesen, andere Bytes bleiben erhalten,
//  Lesedaten einen Takt nach der Adresse.
`timescale 1ns/1ps

module tb_md_vram_ip;

reg clk = 0;
always #4.66 clk = ~clk;

reg  [7:0]   a = 0;
reg  [31:0]  be = 0;
reg  [255:0] d = 0;
reg          we = 0;
wire [255:0] q;
integer i, errors = 0;
reg  [255:0] want;

vram_ip dut(.address(a), .byteena(be), .clock(clk), .data(d), .wren(we), .q(q));

initial begin
	// Wort 3: alle 32 Bytes einzeln schreiben (Byte i = 8'h40 + i)
	for (i = 0; i < 32; i = i + 1) begin
		@(negedge clk); a = 3; be = 32'b1 << i; d = {32{8'h40 + i[7:0]}}; we = 1;
	end
	// Wort 4: nur Byte 5 und 31
	@(negedge clk); a = 4; be = 32'b1 << 5;  d = {32{8'hA5}};
	@(negedge clk);        be = 32'b1 << 31; d = {32{8'h5A}};
	@(negedge clk); we = 0; be = 0; a = 3;
	@(negedge clk);
	for (i = 0; i < 32; i = i + 1) want[8*i +: 8] = 8'h40 + i;
	if (q !== want) begin $display("FAIL: Wort 3 %h", q); errors = errors + 1; end
	a = 4;
	@(negedge clk);
	if (q[8*5 +: 8] !== 8'hA5 || q[8*31 +: 8] !== 8'h5A) begin
		$display("FAIL: Wort 4 %h", q); errors = errors + 1;
	end
	// Byte 6 von Wort 3 überschreiben, Rest bleibt
	@(negedge clk); a = 3; be = 32'b1 << 6; d = {32{8'hEE}}; we = 1;
	@(negedge clk); we = 0; be = 0;
	@(negedge clk);
	want[8*6 +: 8] = 8'hEE;
	if (q !== want) begin $display("FAIL: Wort 3 nach Byte 6 %h", q); errors = errors + 1; end
	if (errors == 0) $display("PASS: tb_md_vram_ip");
	$finish;
end

endmodule
