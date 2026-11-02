// SPDX-License-Identifier: GPL-3.0-or-later
// Simulator: Questa
// Dateien: cores/minimig/rtl/bram.vhd, cores/minimig/rtl/denise_colortable_ram_mf.v
//
// tb_minimig_ram — prüft den RAM-Ersatz des Minimig:
//  dpram 40 bit (Cache-Tags): beide Ports schreiben und lesen über Kreuz,
//    Lesen beim Schreiben liefert am selben Port die neuen Daten
//  dpram cs und enable: cs = 0 sperrt das Schreiben, q = alle Einsen;
//    enable = 0 hält den Port an
//  denise_colortable_ram_mf: 4'b1111 schreibt alles, 4'b0011 (LOCT) nur die
//    untere Hälfte; Lesen derselben Adresse beim Schreiben liefert alte Daten
`timescale 1ns/1ps

module tb_minimig_ram;

reg clk = 0;
always #17.6 clk = ~clk;       // 28,375 MHz wie clk_sys

integer errors = 0, i;
task check(input [255:0] what, input [39:0] got, input [39:0] want);
	if (got !== want) begin
		$display("FAIL: %0s: %h statt %h", what, got, want);
		errors = errors + 1;
	end
endtask

// ---------------------------------------------- dpram 40 bit
reg  [7:0]  aa = 0, ab = 0;
reg  [39:0] da = 0, db = 0;
reg         wa = 0, wb = 0, ena = 1, csa = 1;
wire [39:0] qa, qb;
dpram #(.addr_width(8), .data_width(40)) u_dp
	(.clock(clk), .address_a(aa), .data_a(da), .enable_a(ena), .wren_a(wa), .q_a(qa), .cs_a(csa),
	 .address_b(ab), .data_b(db), .wren_b(wb), .q_b(qb));

// ---------------------------------------------- Farbtabelle
reg  [7:0]  cw = 0, cr = 0;
reg  [31:0] cd = 0;
reg  [3:0]  cbe = 4'hF;
reg         cwe = 0;
wire [31:0] cq;
denise_colortable_ram_mf u_cl
	(.byteena_a(cbe), .clock(clk), .data(cd), .enable(1'b1),
	 .rdaddress(cr), .wraddress(cw), .wren(cwe), .q(cq));

initial begin
	// --- A schreibt, B liest; B schreibt, A liest
	for (i = 0; i < 8; i = i + 1) begin
		@(negedge clk); aa = i; da = 40'hA5_0000_0000 + i; wa = 1;
		@(negedge clk); check("A neu", qa, 40'hA5_0000_0000 + i);
	end
	wa = 0;
	for (i = 0; i < 8; i = i + 1) begin
		@(negedge clk); ab = i;
		@(negedge clk); check("B liest A", qb, 40'hA5_0000_0000 + i);
	end
	ab = 8'h80; db = 40'h5A_1234_5678; wb = 1;
	@(negedge clk); wb = 0; check("B neu", qb, 40'h5A_1234_5678); aa = 8'h80;
	@(negedge clk); check("A liest B", qa, 40'h5A_1234_5678);

	// --- cs = 0: kein Schreiben, q = alle Einsen
	aa = 8'h02; csa = 0; da = 40'h11_1111_1111; wa = 1;
	@(negedge clk); wa = 0; check("cs=0 q", qa, 40'hFF_FFFF_FFFF);
	csa = 1;
	@(negedge clk); check("cs=0 schrieb nicht", qa, 40'hA5_0000_0002);

	// --- enable = 0: Port steht, Adresse und Schreiben wirken nicht
	ena = 0; aa = 8'h03; da = 40'h22_2222_2222; wa = 1;
	@(negedge clk); wa = 0; check("enable=0 hält q", qa, 40'hA5_0000_0002);
	ena = 1;
	@(negedge clk); check("enable=0 schrieb nicht", qa, 40'hA5_0000_0003);

	// --- Farbtabelle: voll schreiben, dann LOCT nur unten
	cw = 8'h10; cd = 32'h0ABC_0DEF; cbe = 4'hF; cwe = 1;
	@(negedge clk); cd = 32'h0111_0222; cbe = 4'h3;
	@(negedge clk); cwe = 0; cr = 8'h10;
	@(negedge clk); check("Farbe LOCT unten neu, oben alt", cq, 32'h0ABC_0222);

	// --- Lesen beim Schreiben derselben Adresse: alte Daten
	cwe = 1; cw = 8'h10; cbe = 4'hF; cd = 32'h0333_0444;
	@(negedge clk); cwe = 0; check("Farbe alt beim Schreiben", cq, 32'h0ABC_0222);
	@(negedge clk); check("Farbe danach neu", cq, 32'h0333_0444);

	if (errors == 0) $display("PASS: tb_minimig_ram");
	else $display("FAIL: %0d Fehler", errors);
	$finish;
end

endmodule
