// SPDX-License-Identifier: GPL-3.0-or-later
// Simulator: Questa
// Dateien: cores/megadrive/rtl/bram.vhd cores/megadrive/rtl/mlab.vhd
//
// tb_md_bram — prüft den Agilex-Ersatz für MegaDrive_MiSTer rtl/bram.vhd und
// rtl/SVP/mlab.vhd:
//  spram (16 Bit, Byte-Freigaben): Schreiben/Lesen, neue Daten beim
//         Schreiben, nur ein Byte schreiben, cs = 0
//  spram (64 Bit, 8 Byte-Freigaben): wie das VRAM des Nuked-MD (256 Bit)
//  dpram (ein Takt, 16 Bit, Byte-Freigaben an beiden Ports)
//  dpram_dif (A 8 Bit / B 16 Bit, ein Takt): Byte-Zuordnung A gerade =
//         unteres Byte von B, Schreiben über beide Ports
//  dpram_difclk (zwei Takte, nur B schreibt): wie die TMSS-ROM
//  mlab (asynchron lesen)
`timescale 1ns/1ps
module tb_md_bram;

reg clk = 0, clk2 = 0;
always #4.66 clk  = ~clk;       // ~107 MHz wie clk_md
always #9.31 clk2 = ~clk2;      // ~53 MHz wie clk_sys

integer errors = 0;
task check(input [255:0] what, input [63:0] got, input [63:0] want);
	if (got !== want) begin
		$display("FAIL: %0s: %h statt %h", what, got, want);
		errors = errors + 1;
	end
endtask

// ------------------------------------------------ spram 16 Bit
reg  [3:0]  s_a = 0;  reg [15:0] s_d = 0;  reg s_we = 0, s_cs = 1;  reg [1:0] s_be = 2'b11;
wire [15:0] s_q;
spram #(.addr_width(4), .data_width(16)) u_sp
	(.clock(clk), .address(s_a), .data(s_d), .wren(s_we), .byteena(s_be), .q(s_q), .cs(s_cs));

// ------------------------------------------------ spram 64 Bit, 8 Byte-Freigaben
reg  [2:0]  w_a = 0;  reg [63:0] w_d = 0;  reg w_we = 0;  reg [7:0] w_be = 8'hFF;
wire [63:0] w_q;
spram #(.addr_width(3), .data_width(64)) u_wide
	(.clock(clk), .address(w_a), .data(w_d), .wren(w_we), .byteena(w_be), .q(w_q));

// ------------------------------------------------ dpram 16 Bit
reg  [4:0]  a_a = 0, b_a = 0;  reg [15:0] a_d = 0, b_d = 0;
reg         a_we = 0, b_we = 0;  reg [1:0] a_be = 2'b11, b_be = 2'b11;
wire [15:0] a_q, b_q;
dpram #(.addr_width(5), .data_width(16)) u_dp
	(.clock(clk), .address_a(a_a), .data_a(a_d), .wren_a(a_we), .byteena_a(a_be), .q_a(a_q),
	 .address_b(b_a), .data_b(b_d), .wren_b(b_we), .byteena_b(b_be), .q_b(b_q));

// ------------------------------------------------ dpram_dif 8 / 16
reg  [5:0]  n_a = 0;  reg [7:0] n_d = 0;  reg n_we = 0;  wire [7:0] n_q;
reg  [4:0]  m_a = 0;  reg [15:0] m_d = 0; reg m_we = 0;  wire [15:0] m_q;
dpram_dif #(.addr_width_a(6), .data_width_a(8), .addr_width_b(5), .data_width_b(16)) u_dif
	(.clock(clk), .address_a(n_a), .data_a(n_d), .wren_a(n_we), .q_a(n_q),
	 .address_b(m_a), .data_b(m_d), .wren_b(m_we), .q_b(m_q));

// ------------------------------------------------ dpram_difclk (B schreibt mit clk2)
reg  [3:0]  r_a = 0, t_a = 0;  reg [15:0] t_d = 0;  reg t_we = 0;  wire [15:0] r_q;
dpram_difclk #(.addr_width_a(4), .data_width_a(16), .addr_width_b(4), .data_width_b(16)) u_rom
	(.clock_a(clk), .address_a(r_a), .q_a(r_q),
	 .clock_b(clk2), .address_b(t_a), .wren_b(t_we), .data_b(t_d));

// ------------------------------------------------ mlab
reg  [3:0]  l_ra = 0, l_wa = 0;  reg [15:0] l_d = 0;  reg l_we = 0;  wire [15:0] l_q;
mlab #(.addr_width(4), .data_width(16)) u_mlab
	(.clock(clk), .rdaddress(l_ra), .wraddress(l_wa), .data(l_d), .wren(l_we), .q(l_q));

integer i;
reg [7:0] lo, hi;

initial begin
	// --- spram 16: voll schreiben, neue Daten sofort
	for (i = 0; i < 16; i = i + 1) begin
		@(negedge clk); s_a = i; s_d = 16'h1100 * i + i; s_we = 1; s_be = 2'b11;
		@(negedge clk); check("spram neue Daten", s_q, 16'h1100 * i + i);
	end
	// nur oberes Byte von Adresse 5 schreiben
	@(negedge clk); s_a = 5; s_d = 16'hABCD; s_be = 2'b10; s_we = 1;
	@(negedge clk); check("spram Byte neu", s_q, {8'hAB, 8'h05}); s_we = 0; s_be = 2'b11;
	@(negedge clk); s_a = 5;
	@(negedge clk); check("spram Byte lesen", s_q, {8'hAB, 8'h05});
	// cs = 0
	@(negedge clk); s_cs = 0; s_a = 6; s_d = 16'h0000; s_we = 1;
	@(negedge clk); check("spram cs=0 q", s_q, 16'hFFFF); s_we = 0; s_cs = 1;
	@(negedge clk);
	@(negedge clk); check("spram cs=0 kein Schreiben", s_q, 16'h6606);

	// --- spram 64: einzelne Bytes
	@(negedge clk); w_a = 2; w_d = 64'h0011223344556677; w_be = 8'hFF; w_we = 1;
	@(negedge clk); w_d = 64'hAAAAAAAAAAAAAAAA; w_be = 8'b0100_0001;
	@(negedge clk); check("spram64 Bytes", w_q, 64'h00AA2233445566AA); w_we = 0;
	@(negedge clk);
	@(negedge clk); check("spram64 lesen", w_q, 64'h00AA2233445566AA);

	// --- dpram: A schreibt, B liest; B schreibt Byte, A liest
	for (i = 0; i < 32; i = i + 1) begin
		@(negedge clk); a_a = i; a_d = 16'hC000 + i * 3; a_we = 1;
		@(negedge clk); check("dpram A neu", a_q, 16'hC000 + i * 3);
	end
	a_we = 0;
	for (i = 0; i < 32; i = i + 1) begin
		@(negedge clk); b_a = i;
		@(negedge clk); check("dpram B liest", b_q, 16'hC000 + i * 3);
	end
	@(negedge clk); b_a = 7; b_d = 16'h5A5A; b_be = 2'b01; b_we = 1;
	@(negedge clk); check("dpram B Byte neu", b_q, {8'hC0, 8'h5A}); b_we = 0; b_be = 2'b11;
	@(negedge clk); a_a = 7;
	@(negedge clk); check("dpram A liest B", a_q, {8'hC0, 8'h5A});

	// --- dpram_dif: A (8 Bit) schreibt Bytes, B (16 Bit) liest Wörter
	for (i = 0; i < 64; i = i + 1) begin
		@(negedge clk); n_a = i; n_d = 8'h40 + i; n_we = 1;
		@(negedge clk); check("dif A neu", n_q, 8'h40 + i);
	end
	n_we = 0;
	for (i = 0; i < 32; i = i + 1) begin
		@(negedge clk); m_a = i;
		lo = 8'h40 + 2*i; hi = 8'h40 + 2*i + 1;   // 8 Bit, sonst wird die Verkettung 32 Bit breit
		@(negedge clk); check("dif B Wort (A gerade = unten)", m_q, {hi, lo});
	end
	// B schreibt Wort, A liest beide Bytes
	@(negedge clk); m_a = 9; m_d = 16'hBEEF; m_we = 1;
	@(negedge clk); check("dif B neu", m_q, 16'hBEEF); m_we = 0;
	@(negedge clk); n_a = 18;
	@(negedge clk); check("dif A unten", n_q, 8'hEF); n_a = 19;
	@(negedge clk); check("dif A oben", n_q, 8'hBE);

	// --- dpram_difclk: B schreibt mit clk2, A liest mit clk
	for (i = 0; i < 16; i = i + 1) begin
		@(negedge clk2); t_a = i; t_d = 16'h7000 + i * 17; t_we = 1;
	end
	@(negedge clk2); t_we = 0;
	for (i = 0; i < 16; i = i + 1) begin
		@(negedge clk); r_a = i;
		@(negedge clk); check("difclk A liest", r_q, 16'h7000 + i * 17);
	end

	// --- mlab: schreiben, asynchron lesen (ohne Takt)
	for (i = 0; i < 16; i = i + 1) begin
		@(negedge clk); l_wa = i; l_d = 16'h0F00 + i; l_we = 1;
	end
	@(negedge clk); l_we = 0;
	for (i = 0; i < 16; i = i + 1) begin
		l_ra = 15 - i; #1;
		check("mlab asynchron", l_q, 16'h0F00 + 15 - i);
	end

	if (errors == 0) $display("PASS: tb_md_bram");
	else             $display("FAIL: %0d Fehler", errors);
	$finish;
end

endmodule
