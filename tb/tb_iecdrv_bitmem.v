// SPDX-License-Identifier: GPL-3.0-or-later
// tb_iecdrv_bitmem — vergleicht cores/c64/rtl/iecdrv_bitmem.v Takt für Takt
// mit einem Verhaltensmodell von MiSTers Original (iecdrv_misc.sv).
//
// Prüft: q_a und q_b in jedem Takt gleich dem Original, bei Zufallszugriffen
// nach dem Muster des Laufwerks — Port B wechselt das Wort höchstens alle 4
// Takte und schreibt einzelne Bits mit Abstand; Port A liest/schreibt frei,
// aber nicht in das Wort, das Port B gerade schreibt (ist auch im Original
// nicht definiert). Zusätzlich gezielte Fälle: Bit schreiben und sofort
// zurücklesen, alle 8 Bits eines Worts nacheinander, Byte über Port A und
// Bits über Port B im selben Wort.
`timescale 1ns/1ps
module tb_iecdrv_bitmem;

localparam AW = 6;                      // klein: Kollisionen werden häufig

reg clk = 0;
always #5 clk = ~clk;

reg  [AW-1:0] address_a = 0;
reg     [7:0] data_a = 0;
reg           wren_a = 0;
reg  [AW+2:0] address_b = 0;
reg           data_b = 0;
reg           wren_b = 0;

wire [7:0] q_a;
wire       q_b;

iecdrv_bitmem #(AW) dut (
	.clock_a(clk), .address_a(address_a), .data_a(data_a), .wren_a(wren_a), .q_a(q_a),
	.clock_b(clk), .address_b(address_b), .data_b(data_b), .wren_b(wren_b), .q_b(q_b)
);

// ---- Referenz: MiSTers iecdrv_bitmem (ein Takt, beide Ports) ---------------
reg [7:0] ref_ram[0:(1<<AW)-1];
reg [7:0] ref_q_a;
reg       ref_q_b;
reg          ra_we, rb_we, rb_d;
reg [AW-1:0] ra_ad;
reg    [7:0] ra_d;
reg [AW+2:0] rb_ad;
always @(posedge clk) begin
	ra_we <= wren_a; ra_ad <= address_a; ra_d <= data_a;
	rb_we <= wren_b; rb_ad <= address_b; rb_d <= data_b;
end
always @(posedge clk) begin
	if (ra_we) begin ref_ram[ra_ad] <= ra_d; ref_q_a <= ra_d; end
	else ref_q_a <= ref_ram[ra_ad];
end
always @(posedge clk) begin
	if (rb_we) begin ref_ram[rb_ad[AW+2:3]][rb_ad[2:0]] <= rb_d; ref_q_b <= rb_d; end
	else ref_q_b <= ref_ram[rb_ad[AW+2:3]][rb_ad[2:0]];
end

// ---- Vergleich -------------------------------------------------------------
integer errors = 0, checks = 0, cyc = 0;
reg     compare = 0;
always @(negedge clk) if (compare) begin
	checks = checks + 1;
	if (q_a !== ref_q_a) begin
		errors = errors + 1;
		if (errors <= 10) $display("FAIL: Takt %0d q_a=%h erwartet %h", cyc, q_a, ref_q_a);
	end
	if (q_b !== ref_q_b) begin
		errors = errors + 1;
		if (errors <= 10) $display("FAIL: Takt %0d q_b=%b erwartet %b", cyc, q_b, ref_q_b);
	end
end
always @(posedge clk) cyc = cyc + 1;

// ---- Anregung --------------------------------------------------------------
integer i, k, hold_b, gap_w;
reg [AW-1:0] wword_b;     // Wort, das Port B zuletzt beschrieben hat
integer      wword_age;   // Takte seit diesem Schreiben

task step; begin @(posedge clk); #1; end endtask

initial begin
	$dumpfile("tb/build/tb_iecdrv_bitmem.vcd");
	$dumpvars(0, tb_iecdrv_bitmem);

	// Speicher über Port A füllen (beide Modelle gleich vorbelegen)
	for (i = 0; i < (1<<AW); i = i + 1) begin
		address_a = i; data_a = $random; wren_a = 1; step;
	end
	wren_a = 0; step; step; step;
	compare = 1;

	// Gezielt: Bit schreiben, sofort und später zurücklesen
	address_b = {6'd5, 3'd3}; data_b = 1; wren_b = 1; step;
	wren_b = 0; step; step; step; step;
	// alle 8 Bits eines Worts nacheinander (Abstand 4 Takte)
	for (k = 0; k < 8; k = k + 1) begin
		address_b = {6'd9, k[2:0]}; data_b = k[0]; wren_b = 1; step;
		wren_b = 0; step; step; step;
	end
	// das Wort über Port A lesen
	address_a = 9; step; step; step;
	// Byte über Port A schreiben, danach Bits über Port B lesen
	address_a = 12; data_a = 8'hA5; wren_a = 1; step; wren_a = 0; step; step; step;
	for (k = 0; k < 8; k = k + 1) begin address_b = {6'd12, k[2:0]}; step; step; end

	// Zufall nach Laufwerksmuster
	hold_b = 0; gap_w = 0; wword_b = 0; wword_age = 100;
	for (i = 0; i < 200000; i = i + 1) begin
		// Port B: Adresse höchstens alle 4 Takte wechseln
		wren_b = 0;
		if (hold_b == 0) begin
			if (($random & 3) == 0) address_b = $random;
			else address_b = address_b + 1;
			hold_b = 4 + ($random & 7);
		end else hold_b = hold_b - 1;
		// vereinzelt ein Bit schreiben: nicht kurz vor einem Wortwechsel,
		// nicht kurz nach dem letzten Schreiben
		if (gap_w == 0 && hold_b >= 3 && ($random & 7) == 0) begin
			wren_b = 1; data_b = $random; gap_w = 6;
			wword_b = address_b[AW+2:3]; wword_age = 0;
		end else if (gap_w) gap_w = gap_w - 1;
		// Port A: zufällig lesen/schreiben, nicht ins Wort, das Port B gerade
		// schreibt oder gleich lesen wird
		address_a = $random; data_a = $random;
		wren_a = (($random & 3) == 0);
		if (wren_a && (address_a == address_b[AW+2:3] || (wword_age < 4 && address_a == wword_b)))
			wren_a = 0;
		step;
		wword_age = wword_age + 1;
	end
	wren_a = 0; wren_b = 0; step; step; step;
	compare = 0;

	if (errors == 0) $display("ok:   %0d Takte verglichen, q_a und q_b gleich dem Original", checks);
	if (errors == 0) $display("PASS: tb_iecdrv_bitmem");
	else             $display("FAIL: tb_iecdrv_bitmem (%0d Abweichungen)", errors);
	$finish;
end

endmodule
