// SPDX-License-Identifier: GPL-3.0-or-later
// tb_avl_slow_cdc — Testbench für sys/de25/avl_slow_cdc.v.
//
// Prüft: Schreiben und Lesen über die Domänengrenze (A 100 MHz, B 50 MHz,
// nicht phasengleich) an ein Registerfeld in B; Avalon-Master hält den
// Zugriff bis waitrequest = 0; je Lesezugriff genau ein readdatavalid mit
// den richtigen Daten; je Zugriff genau ein Puls auf Seite B.

`timescale 1ns/1ps
`default_nettype none

module tb_avl_slow_cdc;

	reg clk_a = 0, clk_b = 0;
	always #5    clk_a = ~clk_a;
	always #10.3 clk_b = ~clk_b;

	reg         rst_a = 1;
	reg  [13:0] a_address = 0;
	reg         a_write = 0, a_read = 0;
	reg  [31:0] a_writedata = 0;
	wire        a_waitrequest;
	wire [31:0] a_readdata;
	wire        a_readdatavalid;

	wire [13:0] b_address;
	wire        b_write, b_read;
	wire [31:0] b_writedata;
	reg  [31:0] b_readdata;

	avl_slow_cdc dut (
		.clk_a(clk_a), .rst_a(rst_a),
		.a_address(a_address), .a_write(a_write), .a_writedata(a_writedata), .a_read(a_read),
		.a_waitrequest(a_waitrequest), .a_readdata(a_readdata), .a_readdatavalid(a_readdatavalid),
		.clk_b(clk_b), .b_address(b_address), .b_write(b_write), .b_writedata(b_writedata),
		.b_read(b_read), .b_readdata(b_readdata)
	);

	// Registerfeld in Domäne B, Lesedaten einen Takt nach b_read
	reg [31:0] regs [0:15];
	integer b_writes = 0, b_reads = 0, rdv = 0;
	always @(posedge clk_b) begin
		if (b_write) begin regs[b_address[5:2]] <= b_writedata; b_writes = b_writes + 1; end
		if (b_read)  begin b_readdata <= regs[b_address[5:2]]; b_reads = b_reads + 1; end
	end

	reg [31:0] last_rd;
	always @(posedge clk_a) if (a_readdatavalid) begin last_rd <= a_readdata; rdv = rdv + 1; end

	integer fails = 0, i;

	task wr(input [13:0] a, input [31:0] d);
		begin
			@(posedge clk_a) begin a_address <= a; a_writedata <= d; a_write <= 1; end
			@(posedge clk_a); while (a_waitrequest) @(posedge clk_a);
			a_write <= 0; a_writedata <= 32'hXXXX_XXXX;
		end
	endtask

	task rd(input [13:0] a, input [31:0] e);
		integer n;
		begin
			n = rdv;
			@(posedge clk_a) begin a_address <= a; a_read <= 1; end
			@(posedge clk_a); while (a_waitrequest) @(posedge clk_a);
			a_read <= 0;
			while (rdv == n) @(posedge clk_a);
			@(negedge clk_a);
			if (last_rd !== e) begin
				$display("FAIL: Lesen 0x%03X = 0x%08X statt 0x%08X", a, last_rd, e);
				fails = fails + 1;
			end
		end
	endtask

	initial begin
		$dumpfile("tb/build/tb_avl_slow_cdc.vcd");
		$dumpvars(0, tb_avl_slow_cdc);
		repeat (4) @(posedge clk_a);
		rst_a <= 0;
		repeat (4) @(posedge clk_a);

		for (i = 0; i < 16; i = i + 1) wr(i * 4, 32'hA500_0000 + i * 32'h0101);
		for (i = 15; i >= 0; i = i - 1) rd(i * 4, 32'hA500_0000 + i * 32'h0101);
		// direkt hintereinander: Schreiben, Lesen derselben Adresse
		wr(14'h008, 32'h1234_5678);
		rd(14'h008, 32'h1234_5678);

		repeat (20) @(posedge clk_a);
		if (b_writes != 17) begin $display("FAIL: %0d Schreibpulse in B statt 17", b_writes); fails = fails + 1; end
		if (b_reads != 17)  begin $display("FAIL: %0d Lesepulse in B statt 17", b_reads); fails = fails + 1; end
		if (rdv != 17)      begin $display("FAIL: %0d readdatavalid statt 17", rdv); fails = fails + 1; end
		if (fails == 0) $display("PASS: tb_avl_slow_cdc");
		$finish;
	end

	initial begin
		#200_000;
		$display("FAIL: Zeitüberschreitung");
		$finish;
	end

endmodule

`default_nettype wire
