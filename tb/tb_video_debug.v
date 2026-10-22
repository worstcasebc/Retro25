// SPDX-License-Identifier: GPL-3.0-or-later
// tb_video_debug — Testbench für sys/de25/video_debug.v.
//
// Prüft: ID; Zähler für VS/DE in clk_vid (DE am Eingang nur mit ce = 1),
// VS/DE in clk_hdmi, Takte/1024, vbuf-Zugriffe (nur ohne waitrequest
// gezählt, Wartetakte getrennt), Status-/Info-Werte; Adressen außerhalb = 0.

`timescale 1ns/1ps
`default_nettype none

module tb_video_debug;

	reg clk_av = 0, clk_vid = 0, clk_hdmi = 0, clk_vbuf = 0;
	always #5    clk_av   = ~clk_av;
	always #6.7  clk_vid  = ~clk_vid;
	always #6.73 clk_hdmi = ~clk_hdmi;
	always #5.1  clk_vbuf = ~clk_vbuf;

	reg [13:0] addr = 0;
	reg        rd = 0;
	wire [31:0] q;
	wire        qv;

	reg core_vs = 0, core_de = 0, in_ce = 0, in_de = 0, out_vs = 0, out_de = 0;
	reg vb_wr = 0, vb_rd = 0, vb_wait = 0, vb_rdv = 0;

	video_debug dut (
		.clk_av(clk_av), .avs_address(addr), .avs_read(rd),
		.avs_readdata(q), .avs_readdatavalid(qv),
		.clk_vid(clk_vid), .core_vs(core_vs), .core_de(core_de), .in_ce(in_ce), .in_de(in_de),
		.clk_hdmi(clk_hdmi), .out_vs(out_vs), .out_de(out_de),
		.clk_vbuf(clk_vbuf), .vbuf_write(vb_wr), .vbuf_read(vb_rd),
		.vbuf_waitrequest(vb_wait), .vbuf_readdatavalid(vb_rdv),
		.status(32'hDEAD_0001), .info0(32'h02D0_0500), .info1(32'h1234_5678)
	);

	integer fails = 0, i;
	reg [31:0] v;

	task read(input [13:0] a, output [31:0] val);
		begin
			@(posedge clk_av) begin addr <= a; rd <= 1; end
			@(posedge clk_av) rd <= 0;
			wait (qv);
			val = q;
			@(posedge clk_av);
		end
	endtask

	task expect(input [13:0] a, input [31:0] e, input [8*40-1:0] msg);
		begin
			read(a, v);
			if (v !== e) begin
				$display("FAIL: %0s: 0x%08X statt 0x%08X", msg, v, e);
				fails = fails + 1;
			end
		end
	endtask

	initial begin
		$dumpfile("tb/build/tb_video_debug.vcd");
		$dumpvars(0, tb_video_debug);

		// 5 VS-Flanken, 7 DE-Flanken am Core; am Eingang 3 DE mit ce, 2 ohne ce
		for (i = 0; i < 5; i = i + 1) begin @(posedge clk_vid) core_vs <= 1; @(posedge clk_vid) core_vs <= 0; end
		for (i = 0; i < 7; i = i + 1) begin @(posedge clk_vid) core_de <= 1; @(posedge clk_vid) core_de <= 0; end
		in_ce <= 1;
		for (i = 0; i < 3; i = i + 1) begin @(posedge clk_vid) in_de <= 1; @(posedge clk_vid) in_de <= 0; end
		@(posedge clk_vid) in_ce <= 0;
		for (i = 0; i < 2; i = i + 1) begin @(posedge clk_vid) in_de <= 1; @(posedge clk_vid) in_de <= 0; end
		// Ausgang: 4 VS, 6 DE
		for (i = 0; i < 4; i = i + 1) begin @(posedge clk_hdmi) out_vs <= 1; @(posedge clk_hdmi) out_vs <= 0; end
		for (i = 0; i < 6; i = i + 1) begin @(posedge clk_hdmi) out_de <= 1; @(posedge clk_hdmi) out_de <= 0; end
		// vbuf: 10 Schreibtakte, davon 4 mit waitrequest; 2 Lesebefehle, 1 wartend; 9 Lesewörter
		@(posedge clk_vbuf) vb_wr <= 1;
		repeat (6) @(posedge clk_vbuf);
		vb_wait <= 1; repeat (4) @(posedge clk_vbuf);
		vb_wait <= 0; vb_wr <= 0; vb_rd <= 1;
		@(posedge clk_vbuf) vb_wait <= 1;
		@(posedge clk_vbuf) vb_wait <= 0;
		@(posedge clk_vbuf) vb_rd <= 0; vb_rdv <= 1;
		repeat (9) @(posedge clk_vbuf);
		vb_rdv <= 0;
		repeat (2100) @(posedge clk_hdmi);
		repeat (10) @(posedge clk_av);

		expect(14'h00, 32'h5232_3544, "ID");
		expect(14'h04, 5, "Core VS");
		expect(14'h08, 7, "Core DE");
		expect(14'h0C, 3, "Eingang DE (nur mit ce)");
		expect(14'h10, 4, "Ausgang VS");
		expect(14'h14, 6, "Ausgang DE");
		read(14'h18, v);
		if (v < 2 || v > 3) begin $display("FAIL: hdmi-Takte/1024 = %0d", v); fails = fails + 1; end
		expect(14'h1C, 6, "vbuf Schreibwörter");
		expect(14'h20, 2, "vbuf Lesebefehle");
		expect(14'h24, 9, "vbuf Lesewörter");
		expect(14'h28, 5, "vbuf Wartetakte");
		expect(14'h2C, 32'hDEAD_0001, "status");
		expect(14'h30, 32'h02D0_0500, "info0");
		expect(14'h34, 32'h1234_5678, "info1");
		expect(14'h38, 0, "außerhalb");
		expect(14'h3FFC, 0, "außerhalb oben");

		if (fails == 0) $display("PASS: tb_video_debug");
		$finish;
	end

endmodule

`default_nettype wire
