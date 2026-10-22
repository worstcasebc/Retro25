// SPDX-License-Identifier: GPL-3.0-or-later
// Simulator: Questa
// Dateien: tb/sdram_chip_model.v cores/z486/pro/src/memory/sdram.v cores/sdram486test/rtl/tester486.v
//
// tb_tester486 — z486-SDRAM-Controller (upstream sdram.v, 85 MHz, HAS_DQM=1,
// 128 MB) mit tester486 an zwei Chip-Modellen: Chip 0 an nCS, Chip 1 an ~nCS
// (wie sys_top_de25: SDRAM_nCS2 = ~SDRAM_nCS).
//   ok:  fehlerfreie Modelle -> zwei Durchläufe (Line Reads mit Wrap und
//        lineare Bursts) ohne Fehler, keine Timing-Verstöße, beide Chips benutzt
//   bad: Gegenprobe, Chip 1 kippt beim Lesen Datenbit 5 -> Fehler gezählt

`timescale 1ns/1ps

module tb_tester486;

reg clk = 0;
always #5.882 clk = ~clk;                 // 85 MHz

reg rst_n = 0;

// ---------------------------------------------------------------- Aufbau
`define SETUP(P, BAD, LBL) \
wire [15:0] P``_dq; \
wire [12:0] P``_a; \
wire        P``_ldqm, P``_udqm, P``_we_n, P``_cas_n, P``_ras_n, P``_cs_n, P``_ba0, P``_ba1; \
wire [31:0] P``_pass, P``_fail; \
tester486 #(.FREQ(85_000_000), .SIM(1)) P``_dut ( \
	.clk(clk), .rst_n(rst_n), .sz(2'd3), .chip(2'd0), \
	.passcount(P``_pass), .failcount(P``_fail), \
	.DRAM_DQ(P``_dq), .DRAM_ADDR(P``_a), .DRAM_LDQM(P``_ldqm), .DRAM_UDQM(P``_udqm), \
	.DRAM_WE_N(P``_we_n), .DRAM_CAS_N(P``_cas_n), .DRAM_RAS_N(P``_ras_n), \
	.DRAM_CS_N(P``_cs_n), .DRAM_BA_0(P``_ba0), .DRAM_BA_1(P``_ba1)); \
sdram_chip_model #(.NAME({LBL, ".chip0"})) P``_chip0 ( \
	.clk(clk), .cke(1'b1), .cs_n(P``_cs_n), .ras_n(P``_ras_n), .cas_n(P``_cas_n), \
	.we_n(P``_we_n), .ba({P``_ba1, P``_ba0}), .a(P``_a), \
	.dqm({P``_udqm, P``_ldqm}), .dq(P``_dq)); \
sdram_chip_model #(.NAME({LBL, ".chip1"}), .BAD_BIT(BAD)) P``_chip1 ( \
	.clk(clk), .cke(1'b1), .cs_n(~P``_cs_n), .ras_n(P``_ras_n), .cas_n(P``_cas_n), \
	.we_n(P``_we_n), .ba({P``_ba1, P``_ba0}), .a(P``_a), \
	.dqm({P``_udqm, P``_ldqm}), .dq(P``_dq));

`SETUP(ok, -1, "ok")
`SETUP(bad, 5, "bad")

// ---------------------------------------------------------------- Ablauf
integer fails = 0;

task check(input cond, input [8*72-1:0] what);
	if (!cond) begin
		fails = fails + 1;
		$display("FAIL: %0s", what);
	end
endtask

initial begin
	repeat (20) @(posedge clk);
	rst_n = 1;

	// zwei Durchläufe: 0 = Line Reads mit Wrap, 1 = lineare Bursts
	fork
		wait (ok_pass == 2);
		begin
			#30_000_000;                      // 30 ms Simulationszeit als Grenze
			$display("FAIL: Zeitlimit, ok_pass=%0d", ok_pass);
		end
	join_any
	disable fork;
	wait (bad_pass == 2);

	$display("ok:  pass=%0d fail=%0d  Modellfehler %0d/%0d  ACT %0d/%0d",
	         ok_pass, ok_fail, ok_chip0.errors, ok_chip1.errors, ok_chip0.acts, ok_chip1.acts);
	$display("bad: pass=%0d fail=%0d  Modellfehler %0d/%0d",
	         bad_pass, bad_fail, bad_chip0.errors, bad_chip1.errors);

	check(ok_pass >= 2, "ok: zwei Durchlaeufe");
	check(ok_fail == 0, "ok: keine Fehler im Tester");
	check(ok_chip0.errors == 0 && ok_chip1.errors == 0, "ok: keine Timing-/Protokollfehler im Modell");
	check(ok_chip0.acts > 1000 && ok_chip1.acts > 1000, "ok: beide Chips benutzt");
	check(bad_fail > 0, "bad: Gegenprobe meldet Fehler");
	check(bad_chip0.errors == 0 && bad_chip1.errors == 0, "bad: Protokoll trotzdem sauber");

	if (fails == 0) $display("PASS: tb_tester486");
	$finish;
end

endmodule
