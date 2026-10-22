// SPDX-License-Identifier: GPL-3.0-or-later
// tb_pll_cfg_de25 — Testbench für sys/de25/pll_cfg_de25.v mit tb/hvio_pll_model.v.
//
// Prüft: Kennung; Rohlesen (Byte-Aufzeichnung, Wort) und Rohschreiben;
// Ablauf wie von sys_top (Cyclone-V-Register 4/3/5/9/8/7, dann 2):
// waitrequest während des Laufs, M/N/C/Ladungspumpe in den Agilex-Registern,
// fremde Bits erhalten, Freigabe-/Kalibrier-/Reset-Bits am Ende, locked;
// Lauf per Debug-Register; Timeout ohne Lock; Prüfen per Zurücklesen: ein
// verlorener Schreibzugriff auf C0 wird durch Wiederholen behoben (Zähler),
// dauerhaft verlorene enden nach drei Versuchen mit Fehlerbit; gestörte
// Lesezugriffe (Nullen) zerstören keine fremden Bits (0x44 oben); nach dem
// Laden liefert der Port eine Weile nur 0xFF — das Einlesen wartet auf Lock
// und übernimmt nie 0xFFFFFFFF; keine Protokollfehler im Modell.

`timescale 1ns/1ps
`default_nettype none

module tb_pll_cfg_de25;

	reg clk = 0;
	always #10 clk = ~clk;   // 50 MHz

	reg rst = 1;

	reg         mgmt_write = 0;
	reg   [5:0] mgmt_address = 0;
	reg  [31:0] mgmt_writedata = 0;
	wire        mgmt_waitrequest;

	reg   [3:0] dbg_address = 0;
	reg         dbg_write = 0, dbg_read = 0;
	reg  [31:0] dbg_writedata = 0;
	wire [31:0] dbg_readdata;

	wire [8:0] avl_address;
	wire       avl_read, avl_write;
	wire [7:0] avl_wdata, avl_rdata;
	wire       locked;
	reg        force_unlock = 0;

	pll_cfg_de25 #(.LOCK_WAIT_MIN(16'd20), .LOCK_TIMEOUT(24'd3000), .RETRY_PAUSE(24'd50),
	               .INIT_DELAY(24'd200)) dut (
		.clk(clk), .rst(rst),
		.mgmt_write(mgmt_write), .mgmt_address(mgmt_address),
		.mgmt_writedata(mgmt_writedata), .mgmt_waitrequest(mgmt_waitrequest),
		.dbg_address(dbg_address), .dbg_write(dbg_write), .dbg_writedata(dbg_writedata),
		.dbg_read(dbg_read), .dbg_readdata(dbg_readdata),
		.core_avl_address(avl_address), .core_avl_read(avl_read), .core_avl_write(avl_write),
		.core_avl_writedata(avl_wdata), .core_avl_readdata(avl_rdata),
		.pll_locked(locked & ~force_unlock & ~pll.not_ready)
	);

	hvio_pll_model #(.ES(0), .LOCK_DELAY(100), .NOT_READY(3000)) pll (
		.clk(clk), .address(avl_address), .read(avl_read), .write(avl_write),
		.writedata(avl_wdata), .readdata(avl_rdata), .locked(locked)
	);

	integer fails = 0;
	integer n;
	reg [31:0] v;

	task check(input [31:0] got, input [31:0] exp, input [8*48-1:0] msg);
		if (got !== exp) begin
			$display("FAIL: %0s: 0x%08X statt 0x%08X", msg, got, exp);
			fails = fails + 1;
		end
	endtask

	task dbg_wr(input [3:0] a, input [31:0] d);
		begin
			@(posedge clk) begin dbg_address <= a; dbg_writedata <= d; dbg_write <= 1; end
			@(posedge clk) dbg_write <= 0;
		end
	endtask

	task dbg_rd(input [3:0] a, output [31:0] d);
		begin
			@(posedge clk) begin dbg_address <= a; dbg_read <= 1; end
			@(posedge clk) dbg_read <= 0;
			@(negedge clk) d = dbg_readdata;
		end
	endtask

	task wait_idle;
		begin
			v = 1;
			while (v[0]) dbg_rd(4'd0, v);
		end
	endtask

	// wie sys_top: einzelne Schreibpulse ohne Rücksicht auf waitrequest
	task mgmt_wr(input [5:0] a, input [31:0] d);
		begin
			@(posedge clk) begin mgmt_address <= a; mgmt_writedata <= d; mgmt_write <= 1; end
			@(posedge clk) mgmt_write <= 0;
			repeat (3) @(posedge clk);
		end
	endtask

	function [31:0] pll_div(input [31:0] div);   // wie getPLLdiv in Main
		pll_div = (div & 1) ? (32'h20000 | (((div / 2) + 1) << 8) | (div / 2))
		                    : (((div / 2) << 8) | (div / 2));
	endfunction

	initial begin
		$dumpfile("tb/build/tb_pll_cfg_de25.vcd");
		$dumpvars(0, tb_pll_cfg_de25);

		repeat (5) @(posedge clk);
		rst <= 0;
		repeat (5) @(posedge clk);
		wait_idle;   // nach dem Reset: auf Lock warten, Konfiguration einlesen
		check(pll.ready_cnt, 0, "Einlesen erst, wenn der Port bereit ist");
		check(dut.hw_q[3], 32'h0780_0085, "gemerkter Stand 0x44 (nicht 0xFFFFFFFF)");
		check(pll.writes, 0, "vor dem ersten Lauf nichts geschrieben");

		// 1) Kennung
		dbg_rd(4'd0, v);
		check(v[31:16], 16'h504C, "Kennung");

		// 2) Rohlesen 0x40
		dbg_wr(4'd2, 32'h040);
		dbg_wr(4'd4, 0);
		wait_idle;
		dbg_rd(4'd3, v);
		check(v, pll.regs[8'h40 >> 2], "Rohlesen 0x40");
		dbg_rd(4'd5, v);  check(v[31:0], 32'hEEEEEEEE, "cap Bytes 0..3 ungültig");
		dbg_rd(4'd6, v);  check(v[15:8], 8'h00, "cap Byte 5 = 0x00");

		// 3) Rohschreiben 0x10 und zurücklesen
		dbg_wr(4'd2, 32'h010);
		dbg_wr(4'd3, 32'hCAFE_0F0E);
		wait_idle;
		check(pll.regs[8'h10 >> 2], 32'hCAFE_0F0E, "Rohschreiben 0x10");
		dbg_wr(4'd3, 32'h1234_5600);   // zurück auf den Startwert
		wait_idle;

		// 4) Ablauf wie von sys_top: M 54, N 1 (bypass), C 7 (ungerade)
		mgmt_wr(6'd4, pll_div(54));
		mgmt_wr(6'd3, 32'h10000);
		mgmt_wr(6'd5, pll_div(7));
		mgmt_wr(6'd9, 2);
		mgmt_wr(6'd8, 7);
		mgmt_wr(6'd7, 32'h8000_0000);
		@(posedge clk) begin mgmt_address <= 2; mgmt_writedata <= 0; mgmt_write <= 1; end
		@(posedge clk) mgmt_write <= 0;
		@(posedge clk);
		if (!mgmt_waitrequest) begin $display("FAIL: waitrequest nach Start nicht aktiv"); fails = fails + 1; end
		wait (!mgmt_waitrequest);
		repeat (3) @(posedge clk);

		check(pll.regs[8'h40 >> 2], (32'd54 << 20) | (32'd1 << 8), "0x40 M 54, N bypass");
		check(pll.regs[8'h44 >> 2], {16'h0780, 15'b00000_00110_01001, 1'b1}, "0x44 Ladungspumpe M 54, fremde Bits");
		check(pll.regs[8'h5C >> 2], (32'd1 << 31) | (32'd3 << 23) | 32'h0000_7E00 | 32'd4, "0x5C C0 = 7, fremde Bits");
		check(pll.regs[8'h10 >> 2], 32'h1234_5601, "0x10 Freigabe");
		check(pll.regs[8'h58 >> 2], 32'h0080_0001, "0x58 Bits 7, 21 gelöscht");
		check(pll.regs[8'h80 >> 2][2], 0, "0x80 Reset-Bit am Ende 0");
		check(pll.regs[8'h48 >> 2][14], 0, "0x48 Kalibrierfreigabe am Ende 0");
		check(pll.regs[8'h88 >> 2][11], 0, "0x88 Anforderung am Ende 0");
		check(locked, 1, "locked");
		dbg_rd(4'd11, v);
		check(v, 32'h0000_0101, "Zähler Start/fertig/Timeout");
		dbg_rd(4'd0, v);
		check(v[2], 0, "kein Timeout");

		// 5) Lauf per Debug: M 297, N 5, C 40 (Startwerte von pll_hdmi_de25)
		dbg_wr(4'd8, pll_div(297));
		dbg_wr(4'd9, pll_div(5));
		dbg_wr(4'd10, pll_div(40));
		dbg_wr(4'd12, 0);
		repeat (3) @(posedge clk);
		wait_idle;
		check(pll.regs[8'h40 >> 2], (32'd297 << 20) | (32'd1 << 17) | (32'd2 << 9) | 32'd3, "0x40 M 297, N 5");
		check(pll.regs[8'h44 >> 2], 32'h0780_0085, "0x44 Ladungspumpe M 297");
		check(pll.regs[8'h5C >> 2], (32'd20 << 23) | 32'h0000_7E00 | 32'd20, "0x5C C0 = 40");

		// 6) Ohne Lock: Timeout, Ablauf endet trotzdem
		force_unlock <= 1;
		dbg_wr(4'd12, 0);
		repeat (3) @(posedge clk);
		wait_idle;
		force_unlock <= 0;
		dbg_rd(4'd0, v);
		check(v[2], 1, "Timeout gemeldet");
		dbg_rd(4'd11, v);
		check(v, 32'h0001_0303, "Zähler nach Timeout");

		// 7) Ein Schreibzugriff auf C0 geht verloren: Prüfen bemerkt es, zweiter
		//    Versuch stimmt (M 297, N 5, C 20 = 148,5 MHz)
		pll.drop_5c = 1;
		dbg_wr(4'd10, pll_div(20));
		dbg_wr(4'd12, 0);
		repeat (3) @(posedge clk);
		wait_idle;
		check(pll.regs[8'h5C >> 2], (32'd10 << 23) | 32'h0000_7E00 | 32'd10, "0x5C C0 = 20 nach Wiederholung");
		dbg_rd(4'd11, v);
		check(v, 32'h0101_0404, "Zähler: eine Wiederholung");
		dbg_rd(4'd0, v);
		check(v[3], 0, "kein Prüffehler");

		// 8) C0 geht dauerhaft verloren: MAX_TRIES (8) Versuche, dann Fehlerbit
		pll.drop_5c = 100;
		dbg_wr(4'd10, pll_div(40));
		dbg_wr(4'd12, 0);
		repeat (3) @(posedge clk);
		wait_idle;
		pll.drop_5c = 0;
		dbg_rd(4'd0, v);
		check(v[3], 1, "Prüffehler gemeldet");
		dbg_rd(4'd11, v);
		check(v, 32'h0801_0505, "Zähler: sieben weitere Wiederholungen");
		// 9) danach normaler Lauf: Fehlerbit wieder weg
		dbg_wr(4'd12, 0);
		repeat (3) @(posedge clk);
		wait_idle;
		check(pll.regs[8'h5C >> 2], (32'd20 << 23) | 32'h0000_7E00 | 32'd20, "0x5C C0 = 40");
		dbg_rd(4'd0, v);
		check(v[3], 0, "Prüffehler gelöscht");

		// 10) Gestörte Lesezugriffe (wie am Board 0x44): Die Konfigurations-
		//     register schreibt der Baustein aus dem gemerkten Stand, gelesen
		//     wird doppelt — fremde Bits bleiben erhalten, Ergebnis stimmt.
		for (n = 1; n <= 7; n = n + 1) begin
			pll.bad_rd = n;          // die ersten n Lesezugriffe des Laufs gestört
			dbg_wr(4'd10, pll_div((n & 1) ? 20 : 40));
			dbg_wr(4'd12, 0);
			repeat (3) @(posedge clk);
			wait_idle;
			check(pll.regs[8'h44 >> 2], 32'h0780_0085, "0x44 fremde Bits bei gestörtem Lesen");
			check(pll.regs[8'h40 >> 2], (32'd297 << 20) | (32'd1 << 17) | (32'd2 << 9) | 32'd3, "0x40 bei gestörtem Lesen");
			check(pll.regs[8'h5C >> 2], (n & 1) ? ((32'd10 << 23) | 32'h0000_7E00 | 32'd10)
			                                    : ((32'd20 << 23) | 32'h0000_7E00 | 32'd20), "0x5C bei gestörtem Lesen");
			check(pll.regs[8'h10 >> 2] & 32'hFFFF_FF00, 32'h1234_5600, "0x10 fremde Bits bei gestörtem Lesen");
			dbg_rd(4'd0, v);
			check(v[3], 0, "kein Prüffehler bei gestörtem Lesen");
		end
		// 11) Länger gestört als MAX_TRIES Versuche: Prüffehler, aber weil nur
		//     aus dem gemerkten Stand geschrieben wird, stimmen die Register
		pll.bad_rd = 20;
		dbg_wr(4'd10, pll_div(40));
		dbg_wr(4'd12, 0);
		repeat (3) @(posedge clk);
		wait_idle;
		pll.bad_rd = 0;
		dbg_rd(4'd0, v);
		check(v[3], 1, "Prüffehler bei Dauerstörung");
		check(pll.regs[8'h44 >> 2], 32'h0780_0085, "0x44 trotz Dauerstörung");
		check(pll.regs[8'h5C >> 2], (32'd20 << 23) | 32'h0000_7E00 | 32'd20, "0x5C trotz Dauerstörung");

		if (pll.errors != 0) begin $display("FAIL: %0d Protokollfehler im Modell", pll.errors); fails = fails + 1; end
		if (fails == 0) $display("PASS: tb_pll_cfg_de25");
		$finish;
	end

	initial begin
		#5_000_000;
		$display("FAIL: Zeitüberschreitung");
		$finish;
	end

endmodule

`default_nettype wire
