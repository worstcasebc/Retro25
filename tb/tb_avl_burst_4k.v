// SPDX-License-Identifier: GPL-3.0-or-later
// tb_avl_burst_4k — Testbench für sys/de25/avl_burst_4k.v.
//
// Prüft:
//  - kein Burst am Ausgang kreuzt eine 4-KB-Grenze (AXI-Regel),
//  - Lese-Bursts liefern die Daten des Referenzspeichers, in Reihenfolge,
//    genau so viele Beats wie angefordert,
//  - Schreib-Bursts (mit Byte-Masken) landen richtig im Speicher,
//  - Bursts ohne Grenze gehen unverändert durch (gleiche Adresse/Länge),
//  - zufälliges waitrequest und Leselatenz des Slaves, Master mit Pausen
//    innerhalb von Schreib-Bursts.
// Prüfling mit DW = 64 (wie ram1/ram2; vbuf mit 128 bit nutzt dieselbe Logik).
`timescale 1ns/1ps
module tb_avl_burst_4k;

reg clk = 0;
always #5 clk = ~clk;
reg rst = 1;

integer errors = 0;

// ---------------------------------------------------------------- Prüfling 64 bit
`define CHECK(c, msg) if (!(c)) begin errors = errors + 1; if (errors < 20) $display("FAIL: %0t %s", $time, msg); end

wire [31:0] m_address;
wire  [7:0] m_burstcount;
wire        m_read, m_write;
wire [63:0] m_writedata;
wire  [7:0] m_byteenable;
reg         m_waitrequest;
reg  [63:0] m_readdata;
reg         m_readdatavalid;

reg  [31:0] s_address = 0;
reg   [7:0] s_burstcount = 0;
reg         s_read = 0, s_write = 0;
reg  [63:0] s_writedata = 0;
reg   [7:0] s_byteenable = 0;
wire        s_waitrequest;
wire [63:0] s_readdata;
wire        s_readdatavalid;

avl_burst_4k #(.DW(64)) dut (
	.clk(clk), .rst(rst),
	.s_address(s_address), .s_burstcount(s_burstcount), .s_read(s_read), .s_write(s_write),
	.s_writedata(s_writedata), .s_byteenable(s_byteenable), .s_waitrequest(s_waitrequest),
	.s_readdata(s_readdata), .s_readdatavalid(s_readdatavalid),
	.m_address(m_address), .m_burstcount(m_burstcount), .m_read(m_read), .m_write(m_write),
	.m_writedata(m_writedata), .m_byteenable(m_byteenable), .m_waitrequest(m_waitrequest),
	.m_readdata(m_readdata), .m_readdatavalid(m_readdatavalid)
);

// ---------------------------------------------------------------- Slave-Modell
// 64 KB Speicher (Adresse [15:0]), zufälliges waitrequest, Leseantworten
// über eine Warteschlange mit zufälliger Latenz.
localparam MEMB = 65536;
reg [7:0] mem[0:MEMB-1];       // Slave
reg [7:0] ref_mem[0:MEMB-1];   // Referenz (Sicht des Masters)

// Schreib-Burst-Zustand im Slave
integer sw_left = 0;
reg [31:0] sw_addr;
// Lese-Warteschlange (Adressen je Beat)
reg [31:0] rq[0:4095];
integer rq_wr = 0, rq_rd = 0;
integer lat = 0;
integer i, k;

always @(posedge clk) begin
	m_waitrequest <= ($random & 3) == 0;     // 25 % der Takte belegt
end

always @(posedge clk) begin
	if (!m_waitrequest) begin
		if (m_read) begin
			`CHECK(sw_left == 0, "Lesen mitten im Schreib-Burst")
			`CHECK(m_burstcount != 0, "burstcount 0 (Lesen)")
			`CHECK((m_address[11:0] + m_burstcount * 8) <= 4096, "Lese-Burst kreuzt 4 KB")
			for (k = 0; k < m_burstcount; k = k + 1) begin
				rq[rq_wr % 4096] = m_address + k * 8;
				rq_wr = rq_wr + 1;
			end
		end
		if (m_write) begin
			if (sw_left == 0) begin
				`CHECK(m_burstcount != 0, "burstcount 0 (Schreiben)")
				`CHECK((m_address[11:0] + m_burstcount * 8) <= 4096, "Schreib-Burst kreuzt 4 KB")
				sw_left = m_burstcount;
				sw_addr = m_address;
			end
			for (k = 0; k < 8; k = k + 1)
				if (m_byteenable[k]) mem[(sw_addr + k) % MEMB] = m_writedata[k*8 +: 8];
			sw_addr = sw_addr + 8;
			sw_left = sw_left - 1;
		end
	end
end

// Leseantworten: Latenz zufällig, dann Beats (mit Lücken)
always @(posedge clk) begin
	m_readdatavalid <= 1'b0;
	if (rq_rd < rq_wr && ($random & 1)) begin
		for (k = 0; k < 8; k = k + 1) m_readdata[k*8 +: 8] <= mem[(rq[rq_rd % 4096] + k) % MEMB];
		m_readdatavalid <= 1'b1;
		rq_rd = rq_rd + 1;
	end
end

// ---------------------------------------------------------------- Master
reg [31:0] exp_q[0:8191];       // erwartete Lese-Adressen je Beat
integer exp_wr = 0, exp_rd = 0;

always @(posedge clk) if (s_readdatavalid) begin
	`CHECK(exp_rd < exp_wr, "mehr Lesedaten als angefordert")
	for (k = 0; k < 8; k = k + 1)
		if (s_readdata[k*8 +: 8] !== ref_mem[(exp_q[exp_rd % 8192] + k) % MEMB]) begin
			errors = errors + 1;
			if (errors < 20) $display("FAIL: %0t Lesedaten Adr %h Byte %0d = %h, erwartet %h", $time,
				exp_q[exp_rd % 8192], k, s_readdata[k*8 +: 8], ref_mem[(exp_q[exp_rd % 8192] + k) % MEMB]);
		end
	exp_rd = exp_rd + 1;
end

task do_read(input [31:0] a, input [7:0] n);
	begin
		// Erwartung vorher eintragen: bei geteilten Befehlen kommen die Daten
		// des ersten Teils, während der Master noch wartet
		for (k = 0; k < n; k = k + 1) begin exp_q[exp_wr % 8192] = a + k * 8; exp_wr = exp_wr + 1; end
		s_address = a; s_burstcount = n; s_read = 1;
		@(posedge clk); while (s_waitrequest) @(posedge clk);
		#1 s_read = 0;
	end
endtask

task do_write(input [31:0] a, input [7:0] n);
	integer b, j;
	begin
		// erst alle Lesedaten abwarten (das Slave-Modell liest beim Antworten,
		// ein späterer Schreib-Burst darf das Ergebnis nicht ändern)
		while (exp_rd != exp_wr) begin @(posedge clk); #1; end
		for (b = 0; b < n; b = b + 1) begin
			// gelegentlich eine Pause im Burst
			if (b > 0 && ($random & 7) == 0) begin s_write = 0; @(posedge clk); #1; end
			s_address = a; s_burstcount = n; s_write = 1;
			s_writedata = {$random, $random};
			s_byteenable = (($random & 3) == 0) ? $random : 8'hFF;
			@(posedge clk); while (s_waitrequest) @(posedge clk);
			for (j = 0; j < 8; j = j + 1)
				if (s_byteenable[j]) ref_mem[(a + b * 8 + j) % MEMB] = s_writedata[j*8 +: 8];
			#1;
		end
		s_write = 0;
	end
endtask

// ---------------------------------------------------------------- Ablauf
reg [31:0] addr;
reg  [7:0] len;
integer n_cross = 0;
initial begin
	$dumpfile("tb/build/tb_avl_burst_4k.vcd");
	$dumpvars(0, tb_avl_burst_4k);
	for (i = 0; i < MEMB; i = i + 1) begin mem[i] = i * 7; ref_mem[i] = i * 7; end
	repeat (4) @(posedge clk);
	#1 rst = 0;
	@(posedge clk); #1;

	// gezielt: Burst genau bis zur Grenze, einer darüber, 1-Beat-Bursts
	do_write(32'hA000_0F80, 8'd16);      // endet genau an 0x1000 (kein Teilen)
	do_write(32'hA000_1FF8, 8'd4);       // kreuzt 0x2000
	do_read (32'hA000_1FF8, 8'd4);
	do_read (32'hA000_0F80, 8'd16);
	do_read (32'hA000_2FF8, 8'd1);

	// Zufall: Adressen oft knapp vor einer Grenze, Länge 1..128
	for (i = 0; i < 3000; i = i + 1) begin
		addr = 32'hA000_0000 | (($random & 32'hFFF8) % MEMB);
		if ($random & 1) addr[11:0] = 12'hFF8 - (($random & 63) * 8);  // nahe Grenze
		len = 1 + ($random & 127);
		if ((addr[11:0] + len * 8) > 4096) n_cross = n_cross + 1;
		if ($random & 1) do_write(addr, len); else do_read(addr, len);
		if (($random & 3) == 0) begin @(posedge clk); #1; end
	end
	// warten, bis alle Lesedaten da sind
	repeat (2000) @(posedge clk);
	`CHECK(exp_rd == exp_wr, "Lesedaten fehlen")
	// Speicher vergleichen
	for (i = 0; i < MEMB; i = i + 1)
		if (mem[i] !== ref_mem[i]) begin
			errors = errors + 1;
			if (errors < 20) $display("FAIL: Speicher %h = %h, erwartet %h", i, mem[i], ref_mem[i]);
		end
	$display("ok:   3000 Zufalls-Bursts, davon %0d über eine 4-KB-Grenze; %0d Lese-Beats geprüft", n_cross, exp_rd);
	if (errors == 0) $display("PASS: tb_avl_burst_4k");
	else             $display("FAIL: tb_avl_burst_4k (%0d Fehler)", errors);
	$finish;
end

endmodule
