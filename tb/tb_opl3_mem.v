// SPDX-License-Identifier: GPL-3.0-or-later
// tb_opl3_mem — vergleicht cores/c64/rtl/opl3_mem.v Takt für Takt mit einem
// Verhaltensmodell von MiSTers opl3_mem (8K x 8 / 4K x 16, beide schreiben).
//
// Prüft: Startinhalt aus opl3prg.mem (über beide Ports gelesen), danach
// Zufallszugriffe beider Ports — data_out1 und data_out2 in jedem Takt gleich
// dem Original (Lesen beim Schreiben liefert den alten Wert). Beide Ports
// schreiben nie gleichzeitig in dasselbe Wort (auch im Original undefiniert).
`timescale 1ns/1ps
module tb_opl3_mem;

localparam FILE = "cores/c64/vendor/rtl/opl3/opl3prg.mem";

reg clk = 0;
always #5 clk = ~clk;

reg         we1 = 0, we2 = 0;
reg  [12:0] addr1 = 0;
reg   [7:0] din1 = 0;
reg  [11:0] addr2 = 0;
reg  [15:0] din2 = 0;
wire  [7:0] dout1;
wire [15:0] dout2;

opl3_mem #(.INIT_FILE(FILE)) dut (
	.clk(clk), .we1(we1), .addr1(addr1), .data_in1(din1), .data_out1(dout1),
	.we2(we2), .addr2(addr2), .data_in2(din2), .data_out2(dout2)
);

// ---- Referenz: Original (ein 16-bit-Speicher, Byte-Zugriff an Port 1) ------
reg [15:0] ref_ram[0:4095];
reg  [7:0] ref_q1;
reg [15:0] ref_q2;
initial $readmemh(FILE, ref_ram);
always @(posedge clk) begin
	ref_q1 <= addr1[0] ? ref_ram[addr1[12:1]][15:8] : ref_ram[addr1[12:1]][7:0];
	ref_q2 <= ref_ram[addr2];
	if (we1) begin
		if (addr1[0]) ref_ram[addr1[12:1]][15:8] <= din1;
		else          ref_ram[addr1[12:1]][7:0]  <= din1;
	end
	if (we2) ref_ram[addr2] <= din2;
end

integer errors = 0, checks = 0, i;
reg     compare = 0;
always @(negedge clk) if (compare) begin
	checks = checks + 1;
	if (dout1 !== ref_q1) begin
		errors = errors + 1;
		if (errors <= 10) $display("FAIL: %0t data_out1=%h erwartet %h (addr1 %h)", $time, dout1, ref_q1, addr1);
	end
	if (dout2 !== ref_q2) begin
		errors = errors + 1;
		if (errors <= 10) $display("FAIL: %0t data_out2=%h erwartet %h", $time, dout2, ref_q2);
	end
end

task step; begin @(posedge clk); #1; end endtask

initial begin
	$dumpfile("tb/build/tb_opl3_mem.vcd");
	$dumpvars(0, tb_opl3_mem);
	step;
	compare = 1;
	// Startinhalt: alle Bytes über Port 1, alle Wörter über Port 2
	for (i = 0; i < 8192; i = i + 1) begin
		addr1 = i; addr2 = i[11:0]; step;
	end
	if (errors == 0) $display("ok:   Startinhalt aus opl3prg.mem gleich");
	// Zufall
	for (i = 0; i < 200000; i = i + 1) begin
		addr1 = $random; din1 = $random; addr2 = $random; din2 = $random;
		we1 = (($random & 3) == 0);
		we2 = (($random & 3) == 0);
		if (we1 && we2 && addr1[12:1] == addr2) we2 = 0;
		step;
	end
	we1 = 0; we2 = 0; step; step;
	compare = 0;
	if (errors == 0) $display("ok:   %0d Takte verglichen, beide Ports gleich dem Original", checks);
	if (errors == 0) $display("PASS: tb_opl3_mem");
	else             $display("FAIL: tb_opl3_mem (%0d Abweichungen)", errors);
	$finish;
end

endmodule
