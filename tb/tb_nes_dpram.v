// SPDX-License-Identifier: GPL-3.0-or-later
// Simulator: Questa
// Dateien: cores/nes/rtl/dpram.vhd
//
// tb_nes_dpram — prüft den Agilex-Ersatz für NES_MiSTer rtl/dpram.vhd:
//  spram: Schreiben/Lesen, neue Daten beim Schreiben, cs = 0 (q = 1…1,
//         kein Schreiben)
//  dpram: zwei Takte (clk85-artig 11,6 ns und clk-artig 46,5 ns),
//         A schreibt -> B liest, B schreibt -> A liest, neue Daten am
//         schreibenden Port, zufällige Folge gegen ein Referenzmodell
`timescale 1ns/1ps
module tb_nes_dpram;

reg clk_a = 0, clk_b = 0;
always #5.82  clk_a = ~clk_a;
always #23.28 clk_b = ~clk_b;

integer errors = 0;
task check(input [255:0] what, input [15:0] got, input [15:0] want);
	if (got !== want) begin
		$display("FAIL: %0s: %h statt %h", what, got, want);
		errors = errors + 1;
	end
endtask

// ---------------- spram (4 Adressbits, 8 Datenbits) ----------------
reg  [3:0] s_addr = 0;
reg  [7:0] s_data = 0;
reg        s_wren = 0, s_cs = 1;
wire [7:0] s_q;
spram #(.addr_width(4), .data_width(8)) u_spram
	(.clock(clk_a), .address(s_addr), .data(s_data), .wren(s_wren), .q(s_q), .cs(s_cs));

// ---------------- dpram (6 Adressbits, 16 Datenbits) ---------------
reg  [5:0]  a_addr = 0, b_addr = 0;
reg  [15:0] a_data = 0, b_data = 0;
reg         a_wren = 0, b_wren = 0;
wire [15:0] a_q, b_q;
dpram #(.widthad_a(6), .width_a(16)) u_dpram
	(.address_a(a_addr), .address_b(b_addr), .clock_a(clk_a), .clock_b(clk_b),
	 .data_a(a_data), .data_b(b_data), .wren_a(a_wren), .wren_b(b_wren),
	 .q_a(a_q), .q_b(b_q));

reg [15:0] model [0:63];
integer i, n, adr;

initial begin
	// spram: 16 Werte schreiben (neue Daten sofort am Ausgang)
	for (i = 0; i < 16; i = i + 1) begin
		@(negedge clk_a); s_addr = i; s_data = 8'hA0 ^ (i * 7); s_wren = 1;
		@(negedge clk_a); check("spram neue Daten", s_q, 8'hA0 ^ (i * 7));
	end
	s_wren = 0;
	for (i = 0; i < 16; i = i + 1) begin
		@(negedge clk_a); s_addr = i;
		@(negedge clk_a); check("spram lesen", s_q, 8'hA0 ^ (i * 7));
	end
	// cs = 0: Ausgang FF, Schreiben gesperrt
	@(negedge clk_a); s_cs = 0; s_addr = 3; s_data = 8'h55; s_wren = 1;
	@(negedge clk_a); check("spram cs=0 q", s_q, 8'hFF); s_wren = 0; s_cs = 1;
	@(negedge clk_a);
	@(negedge clk_a); check("spram cs=0 kein Schreiben", s_q, 8'hA0 ^ (3 * 7));

	// dpram: A schreibt alle Adressen, B liest
	for (i = 0; i < 64; i = i + 1) begin
		@(negedge clk_a); a_addr = i; a_data = 16'h1000 + i * 16'h0101; a_wren = 1;
		@(negedge clk_a); check("dpram A neue Daten", a_q, 16'h1000 + i * 16'h0101);
		model[i] = 16'h1000 + i * 16'h0101;
	end
	a_wren = 0;
	for (i = 0; i < 64; i = i + 1) begin
		@(negedge clk_b); b_addr = i;
		@(negedge clk_b); check("dpram B liest A", b_q, model[i]);
	end
	// B schreibt jede zweite Adresse, A liest alles
	for (i = 0; i < 64; i = i + 2) begin
		@(negedge clk_b); b_addr = i; b_data = 16'hBEEF ^ i; b_wren = 1;
		@(negedge clk_b); check("dpram B neue Daten", b_q, 16'hBEEF ^ i);
		model[i] = 16'hBEEF ^ i;
	end
	b_wren = 0;
	for (i = 0; i < 64; i = i + 1) begin
		@(negedge clk_a); a_addr = i;
		@(negedge clk_a); check("dpram A liest B", a_q, model[i]);
	end
	// Zufallsfolge: A schreibt/liest schnell, B liest langsam (verschiedene
	// Adressen in jedem B-Takt nicht garantiert -> nur Adressen prüfen, die A
	// in dieser Zeit nicht schreibt: A schreibt nur obere Hälfte, B liest untere)
	for (n = 0; n < 400; n = n + 1) begin
		@(negedge clk_a);
		adr = 32 + ($random & 31);
		a_addr = adr; a_wren = $random & 1; a_data = $random;
		if (a_wren) model[adr] = a_data;
		@(negedge clk_a);
		if (a_wren) check("dpram A zufall neu", a_q, model[adr]);
		else        check("dpram A zufall lesen", a_q, model[adr]);
	end
	a_wren = 0;
	for (i = 0; i < 64; i = i + 1) begin
		@(negedge clk_b); b_addr = i;
		@(negedge clk_b); check("dpram B Endstand", b_q, model[i]);
	end

	if (errors == 0) $display("PASS: tb_nes_dpram");
	else             $display("FAIL: %0d Fehler", errors);
	$finish;
end

endmodule
