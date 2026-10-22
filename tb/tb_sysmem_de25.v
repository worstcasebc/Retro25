// SPDX-License-Identifier: GPL-3.0-or-later
// tb_sysmem_de25 — Testbench für sys/de25/sysmem_de25.v.
//
// Prüft:
//   1. Reset: reset_out bleibt nach hps_ninit_done = 0 noch INIT_CYCLES Takte
//      aktiv, folgt danach reset_core_req
//   2. Adressfenster: MiSTer-Wortadressen -> physische Byte-Adressen mit
//      Bits 31..29 = 101 (ram1/ram2 64 bit, vbuf 128 bit), auch für
//      Adressen außerhalb 0x2000_0000–0x3FFF_FFFF (bleiben im Fenster)
//   3. Alle übrigen Signale werden unverändert durchgereicht (beide
//      Richtungen), Takte ebenso — außer byteenable beim Lesen: immer FF
//      (ram1/ram2; F2SDRAM liefert sonst nur die freigegebenen Bytes)
//   4. halt_req: angehaltener Port nimmt keinen Befehl an, halt_idle meldet
//      leere Ports (ein Port ohne bisherigen Zugriff gilt als leer);
//      nach halt_req = 0 läuft der Verkehr weiter
//   5. Core-Reset mitten im ram1-Schreib-Burst: der Burst wird mit
//      byteenable = 0 zu Ende geschrieben
// Die f2s_halt_de25-Einzelheiten prüft tb_f2s_halt_de25.

`timescale 1ns/1ps
`default_nettype none

module tb_sysmem_de25;

	reg clk = 1'b0;
	always #5 clk = ~clk;

	reg ninit = 1'b1, core_req = 1'b0;
	wire clock, reset_out;

	reg  [28:0] r1a = 0, r2a = 0;   reg [27:0] va = 0;
	reg   [7:0] r1b = 0, r2b = 0, vb = 0;
	reg         r1r = 0, r1w = 0, r2r = 0, r2w = 0, vr = 0, vw = 0;
	reg  [63:0] r1d = 0, r2d = 0;   reg [127:0] vd = 0;
	reg   [7:0] r1e = 0, r2e = 0;   reg  [15:0] ve = 0;
	wire        r1wait, r2wait, vwait, r1v, r2v, vv;
	wire [63:0] r1q, r2q;           wire [127:0] vq;

	wire        f1c, f2c, fvc;
	wire [31:0] f1a, f2a, fva;
	wire  [7:0] f1b, f2b, fvb, f1e, f2e;
	wire [15:0] fve;
	wire        f1r, f1w, f2r, f2w, fvr, fvw;
	wire [63:0] f1d, f2d;           wire [127:0] fvd;
	reg         f1wait = 0, f2wait = 0, fvwait = 0, f1v = 0, f2v = 0, fvv = 0;
	reg  [63:0] f1q = 0, f2q = 0;   reg [127:0] fvq = 0;

	reg ram1_clk = 0, ram2_clk = 0, vbuf_clk = 0;
	reg run = 1;                     // Port-Takte frei laufen lassen (auch im Init-Reset)
	always #4 if (run) ram1_clk = ~ram1_clk;
	always #7 if (run) ram2_clk = ~ram2_clk;
	always #5 if (run) vbuf_clk = ~vbuf_clk;
	reg halt_req = 0;
	wire [2:0] halt_idle;

	sysmem_de25 #(.INIT_CYCLES(20)) dut (
		.clk_100_in(clk), .hps_ninit_done(ninit), .clock(clock), .reset_out(reset_out),
		.reset_hps_cold_req(1'b0), .reset_hps_warm_req(1'b0), .reset_core_req(core_req),
		.halt_req(halt_req), .halt_idle(halt_idle),
		.ram1_clk(ram1_clk), .ram1_address(r1a), .ram1_burstcount(r1b), .ram1_waitrequest(r1wait),
		.ram1_readdata(r1q), .ram1_readdatavalid(r1v), .ram1_read(r1r), .ram1_writedata(r1d),
		.ram1_byteenable(r1e), .ram1_write(r1w),
		.ram2_clk(ram2_clk), .ram2_address(r2a), .ram2_burstcount(r2b), .ram2_waitrequest(r2wait),
		.ram2_readdata(r2q), .ram2_readdatavalid(r2v), .ram2_read(r2r), .ram2_writedata(r2d),
		.ram2_byteenable(r2e), .ram2_write(r2w),
		.vbuf_clk(vbuf_clk), .vbuf_address(va), .vbuf_burstcount(vb), .vbuf_waitrequest(vwait),
		.vbuf_readdata(vq), .vbuf_readdatavalid(vv), .vbuf_read(vr), .vbuf_writedata(vd),
		.vbuf_byteenable(ve), .vbuf_write(vw),
		.f2s_ram1_clk(f1c), .f2s_ram1_address(f1a), .f2s_ram1_burstcount(f1b),
		.f2s_ram1_waitrequest(f1wait), .f2s_ram1_readdata(f1q), .f2s_ram1_readdatavalid(f1v),
		.f2s_ram1_read(f1r), .f2s_ram1_writedata(f1d), .f2s_ram1_byteenable(f1e), .f2s_ram1_write(f1w),
		.f2s_ram2_clk(f2c), .f2s_ram2_address(f2a), .f2s_ram2_burstcount(f2b),
		.f2s_ram2_waitrequest(f2wait), .f2s_ram2_readdata(f2q), .f2s_ram2_readdatavalid(f2v),
		.f2s_ram2_read(f2r), .f2s_ram2_writedata(f2d), .f2s_ram2_byteenable(f2e), .f2s_ram2_write(f2w),
		.f2s_vbuf_clk(fvc), .f2s_vbuf_address(fva), .f2s_vbuf_burstcount(fvb),
		.f2s_vbuf_waitrequest(fvwait), .f2s_vbuf_readdata(fvq), .f2s_vbuf_readdatavalid(fvv),
		.f2s_vbuf_read(fvr), .f2s_vbuf_writedata(fvd), .f2s_vbuf_byteenable(fve), .f2s_vbuf_write(fvw)
	);

	integer fails = 0, n;

	task check(input cond, input [8*60-1:0] msg);
		if (!cond) begin
			$display("FAIL: %0s (t=%0t)", msg, $time);
			fails = fails + 1;
		end
	endtask

	initial begin
		$dumpfile("tb/build/tb_sysmem_de25.vcd");
		$dumpvars(0, tb_sysmem_de25);

		// 1: Reset
		repeat (3) @(posedge clk);
		check(reset_out, "Reset aktiv, solange ninit_done = 1");
		ninit = 1'b0;
		n = 0;
		while (reset_out && n < 100) begin @(posedge clk); n = n + 1; end
		check(n >= 20 && n <= 23, "Reset nicht ~INIT_CYCLES lang");
		core_req = 1'b1; #1;
		check(reset_out, "reset_core_req wirkt nicht");
		core_req = 1'b0; #1;
		check(!reset_out, "Reset bleibt hängen");
		// Ports aus dem Init-Reset holen (braucht die Port-Takte), dann anhalten
		run = 1; repeat (20) @(posedge clk); run = 0; #20;
		ram1_clk = 0; ram2_clk = 0; vbuf_clk = 0; #1;

		// 2: Adressfenster
		r1a = 29'h0600_0000; r2a = 29'h0400_0001; va = 28'h020_0000; #1;
		check(f1a == 32'hB000_0000, "ram1 0x0600_0000 -> 0xB000_0000");
		check(f2a == 32'hA000_0008, "ram2 0x0400_0001 -> 0xA000_0008");
		check(fva == 32'hA200_0000, "vbuf 0x020_0000 -> 0xA200_0000");
		r1a = 29'h0000_0010; va = 28'hFFF_FFFF; #1;
		check(f1a == 32'hA000_0080, "ram1 unter 0x2000_0000 bleibt im Fenster");
		check(fva == 32'hBFFF_FFF0, "vbuf Maximum -> 0xBFFF_FFF0");
		r1a = 29'h1FFF_FFFF; #1;
		check(f1a == 32'hBFFF_FFF8, "ram1 Maximum -> 0xBFFF_FFF8");
		// ab hier Adressen ohne 4-KB-Grenze im Burst — sonst teilt avl_burst_4k
		// (eigene Testbench tb_avl_burst_4k) und Länge/waitrequest ändern sich
		r1a = 29'h0400_0000; r2a = 29'h0400_0000; va = 28'h0200_0000; #1;

		// 3: Durchreichen
		r1b = 8'd64; r1r = 0; r1w = 1; r1d = 64'h0123_4567_89AB_CDEF; r1e = 8'h5A;
		r2b = 8'd3;  r2r = 1; r2d = 64'hFEDC_BA98_7654_3210; r2e = 8'hC3;
		vb = 8'd16; vw = 1; vd = {4{32'hDEAD_BEEF}}; ve = 16'hF00F;
		f1wait = 1; f1v = 1; f1q = 64'h1111_2222_3333_4444;
		f2wait = 0; f2v = 1; f2q = 64'h5555_6666_7777_8888;
		fvwait = 1; fvv = 1; fvq = {4{32'hCAFE_F00D}};
		#1;
		check(f1b == 64 && !f1r && f1w && f1d == r1d && f1e == 8'h5A, "ram1 Richtung DDR");
		check(r1wait && r1v && r1q == f1q, "ram1 Richtung Core");
		check(f2b == 3 && f2r && !f2w && f2d == r2d, "ram2 Richtung DDR");
		// Lesen immer mit allen Bytes (sonst liefert F2SDRAM nur die freigegebenen)
		check(f2e == 8'hFF, "ram2 lesen nicht mit byteenable FF");
		r1w = 0; r1r = 1; #1;
		check(f1r && f1e == 8'hFF, "ram1 lesen nicht mit byteenable FF");
		r1w = 1; r1r = 0; #1;
		check(!r2wait && r2v && r2q == f2q, "ram2 Richtung Core");
		check(fvb == 16 && !fvr && fvw && fvd == vd && fve == 16'hF00F, "vbuf Richtung DDR");
		check(vwait && vv && vq == fvq, "vbuf Richtung Core");
		// Takte (ohne Lesedaten: ein readdatavalid ohne Befehl zählte f2s_halt_de25 mit)
		f1v = 0; f2v = 0; fvv = 0;
		ram1_clk = 1; vbuf_clk = 1; #1;
		check(f1c && !f2c && fvc, "Takte durchgereicht");

		// 4: halt_req
		r1r = 0; r1w = 0; r2r = 0; vw = 0; r1e = 8'hFF;
		f1wait = 0; f2wait = 0; fvwait = 0; f1v = 0; f2v = 0; fvv = 0;
		run = 1;
		repeat (10) @(posedge clk);
		check(halt_idle == 3'b010, "halt_idle ohne halt: nur ram2 (nie benutzt) leer");
		halt_req = 1;
		n = 0;
		while (halt_idle != 3'b111 && n < 3000) begin @(posedge clk); n = n + 1; end
		check(halt_idle == 3'b111, "halt_idle kommt nicht");
		@(posedge vbuf_clk); vr = 1; vb = 8'd2;
		repeat (10) begin
			@(posedge vbuf_clk); #1;
			check(!fvr && vwait, "vbuf-Lesen trotz halt weitergegeben");
		end
		halt_req = 0;
		n = 0;
		while (!fvr && n < 20) begin @(posedge vbuf_clk); #1; n = n + 1; end
		check(fvr && !vwait, "vbuf nach halt_req = 0 nicht frei");
		@(posedge vbuf_clk); vr = 0;
		fvv = 1; repeat (2) @(posedge vbuf_clk); fvv = 0;   // die zwei Lesedaten
		check(halt_idle[2] == 1'b0, "halt_idle bleibt nach halt_req = 0");

		// 5: Core-Reset mitten im ram1-Schreib-Burst
		@(posedge ram1_clk); r1b = 8'd4; r1w = 1; r1e = 8'hFF;
		@(posedge ram1_clk); r1w = 0;                    // ein Beat, dann Reset
		core_req = 1;
		n = 0;
		repeat (40) begin
			@(posedge ram1_clk); #1;
			if (f1w && !f1wait) begin
				check(f1e == 8'h00, "Ersatz-Beat mit byteenable != 0");
				n = n + 1;
			end
		end
		check(n == 3, "Burst nicht mit 3 Ersatz-Beats beendet"); if (n != 3) $display("  %0d Ersatz-Beats, wr_left %0d blk %b", n, dut.halt_ram1.wr_left_q, dut.halt_ram1.blk_q);
		check(r1wait, "ram1 im Core-Reset nicht angehalten");
		core_req = 0;
		run = 0;

		if (fails == 0) $display("PASS: tb_sysmem_de25");
		$finish;
	end

endmodule

`default_nettype wire
