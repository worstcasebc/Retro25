// SPDX-License-Identifier: GPL-3.0-or-later
// Simulator: Questa
// Dateien: cores/snes/rtl/bram.vhd
//
// tb_snes_bram — prüft die SNES-Erweiterungen des RAM-Ersatzes:
//  dpram 15 bit (CGRAM): krumme Breite, beide Ports schreiben/lesen
//  dpram_dif 16/32 (OAM): Port A 16 bit wählt mit Bit 0 die Hälfte
//  dpram_difclk mit clock0 = not clock1 (CX4 DATA_RAM): beide Ports
//    schreiben; jeder Port liest, was der andere geschrieben hat; Port A
//    liest beim Schreiben die neuen Daten
//  spram 8 bit (Grundfall)
`timescale 1ns/1ps

module tb_snes_bram;

reg clk = 0;
always #23.28 clk = ~clk;      // 21,477 MHz wie clk_sys
wire nclk = ~clk;

integer errors = 0, i;
task check(input [255:0] what, input [31:0] got, input [31:0] want);
	if (got !== want) begin
		$display("FAIL: %0s: %h statt %h", what, got, want);
		errors = errors + 1;
	end
endtask

// ---------------------------------------------- dpram 15 bit
reg  [7:0]  c_aa = 0, c_ab = 0;  reg [14:0] c_da = 0, c_db = 0;  reg c_wa = 0, c_wb = 0;
wire [14:0] c_qa, c_qb;
dpram #(.addr_width(8), .data_width(15)) u_cg
	(.clock(clk), .address_a(c_aa), .data_a(c_da), .wren_a(c_wa), .q_a(c_qa),
	 .address_b(c_ab), .data_b(c_db), .wren_b(c_wb), .q_b(c_qb));

// ---------------------------------------------- dpram_dif 16 / 32
reg  [7:0]  o_aa = 0;  reg [6:0] o_ab = 0;  reg [15:0] o_da = 0;  reg o_wa = 0;
wire [15:0] o_qa;  wire [31:0] o_qb;
dpram_dif #(.addr_width_a(8), .data_width_a(16), .addr_width_b(7), .data_width_b(32)) u_oam
	(.clock(clk), .address_a(o_aa), .data_a(o_da), .wren_a(o_wa), .q_a(o_qa),
	 .address_b(o_ab), .q_b(o_qb));

// ---------------------------------------------- dpram_difclk, not CLK / CLK
reg  [11:0] x_aa = 0, x_ab = 0;  reg [7:0] x_da = 0, x_db = 0;  reg x_wa = 0, x_wb = 0;
wire [7:0]  x_qa, x_qb;
dpram_difclk #(.addr_width_a(12), .data_width_a(8), .addr_width_b(12), .data_width_b(8)) u_cx4
	(.clock0(nclk), .address_a(x_aa), .data_a(x_da), .wren_a(x_wa), .q_a(x_qa),
	 .clock1(clk),  .address_b(x_ab), .data_b(x_db), .wren_b(x_wb), .q_b(x_qb));

// ---------------------------------------------- spram 8 bit
reg  [4:0] s_a = 0;  reg [7:0] s_d = 0;  reg s_we = 0;
wire [7:0] s_q;
spram #(.addr_width(5), .data_width(8)) u_sp
	(.clock(clk), .address(s_a), .data(s_d), .wren(s_we), .q(s_q));

initial begin
	// --- dpram 15: A schreibt, B liest; B schreibt, A liest
	for (i = 0; i < 4; i = i + 1) begin
		@(negedge clk); c_aa = i; c_da = 15'h4000 | (i * 15'h111); c_wa = 1;
	end
	@(negedge clk); c_wa = 0; c_ab = 2;
	@(negedge clk); check("cg B liest A", c_qb, 15'h4000 | (2 * 15'h111));
	c_ab = 7; c_db = 15'h7ABC; c_wb = 1;
	@(negedge clk); c_wb = 0; check("cg B neu", c_qb, 15'h7ABC); c_aa = 7;
	@(negedge clk); check("cg A liest B (15 bit)", c_qa, 15'h7ABC);

	// --- OAM: A schreibt zwei Hälften, B liest 32 bit
	@(negedge clk); o_aa = 8'h10; o_da = 16'h1111; o_wa = 1;
	@(negedge clk); o_aa = 8'h11; o_da = 16'h2222;
	@(negedge clk); o_wa = 0; o_ab = 7'h08;
	@(negedge clk); check("oam B 32 bit (A gerade = unten)", o_qb, 32'h2222_1111);
	o_aa = 8'h11;
	@(negedge clk); check("oam A obere Hälfte", o_qa, 16'h2222);

	// --- CX4: Port A (not CLK) schreibt 0..15, Port B (CLK) liest sie
	for (i = 0; i < 16; i = i + 1) begin
		@(posedge clk); x_aa = i; x_da = 8'h30 + i; x_wa = 1;   // vor der fallenden Flanke
		@(negedge clk); #1;
		check("cx4 A neu", x_qa, 8'h30 + i);
	end
	@(posedge clk); x_wa = 0;
	for (i = 0; i < 16; i = i + 1) begin
		@(negedge clk); x_ab = i;
		@(posedge clk); #1;
		check("cx4 B liest A", x_qb, 8'h30 + i);
	end
	// Port B (CLK) schreibt, Port A (not CLK) liest
	@(negedge clk); x_ab = 12'h800; x_db = 8'hA5; x_wb = 1;
	@(posedge clk); #1; x_wb = 0;
	@(posedge clk); x_aa = 12'h800;
	@(negedge clk); #1;
	check("cx4 A liest B", x_qa, 8'hA5);
	@(negedge clk); x_ab = 12'h800;
	@(posedge clk); #1;
	check("cx4 B liest eigenes", x_qb, 8'hA5);

	// --- spram
	@(negedge clk); s_a = 3; s_d = 8'h5C; s_we = 1;
	@(negedge clk); s_we = 0; check("spram neu", s_q, 8'h5C);

	if (errors == 0) $display("PASS: tb_snes_bram");
	$finish;
end

endmodule
