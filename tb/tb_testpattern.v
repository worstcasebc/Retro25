// SPDX-License-Identifier: GPL-3.0-or-later
// tb_testpattern — Testcore cores/testpattern (module emu) allein.
//
// Simulator: Questa
// Dateien: cores/testpattern/testpattern.sv cores/testpattern/ddr_test.v tb/de25_stubs/de25_stubs.v
// Include: sys/include cores/testpattern
//
// Prüft das Bild an den emu-Ausgängen, abgetastet mit CLK_VIDEO (CE_PIXEL
// muss immer 1 sein): 1650 Takte je Zeile, 1280 sichtbare Pixel, 750 Zeilen,
// 720 sichtbare, HS 40 Takte und VS 5 Zeilen lang (Beginn mit HS), Syncs high-aktiv, außerhalb von
// DE schwarz. Dazu Stichproben der Farbbalken und das wandernde Quadrat.
// sys_top_de25 als Ganzes prüft Quartus (MiSTers Quellen nutzen Bezeichner
// vor ihrer Deklaration — Questa lehnt das ab).

`timescale 1ps/1ps
`default_nettype none

module tb_testpattern;

	reg clk50 = 1'b0;
	always #10000 clk50 = ~clk50;

	reg reset = 1'b1;
	initial #2_000_000 reset = 1'b0;

	// Quadrat kurz vor die Ränder setzen (rechts, oben), damit es in den drei
	// simulierten Bildern abprallt. Fehler auf dem Board: bei 0 lief die
	// Position nach 2044 bzw. 1021 über und das Quadrat blieb hängen.
	initial begin
		#1;
		dut.box_x = 11'd1212; dut.box_dx = 1'b1;
		dut.box_y = 10'd3;    dut.box_dy = 1'b0;
	end

	wire [45:0] hps_bus;
	wire        clk_video, ce_pixel, hs, vs, de;
	wire  [7:0] r, g, b;

	// Leitungen, die sys_top sonst treibt
	assign hps_bus[45:38] = 8'd0;
	assign hps_bus[35:16] = 20'd0;

	emu dut (
		.CLK_50M(clk50), .RESET(reset), .HPS_BUS(hps_bus),
		.CLK_VIDEO(clk_video), .CE_PIXEL(ce_pixel), .VIDEO_ARX(), .VIDEO_ARY(),
		.VGA_R(r), .VGA_G(g), .VGA_B(b), .VGA_HS(hs), .VGA_VS(vs), .VGA_DE(de),
		.VGA_F1(), .VGA_SL(), .VGA_SCALER(), .VGA_DISABLE(),
		.HDMI_WIDTH(12'd0), .HDMI_HEIGHT(12'd0), .HDMI_FREEZE(), .HDMI_BLACKOUT(), .HDMI_BOB_DEINT(),
		.LFB_FMT(6'd0), .LFB_BASE(32'd0), .LFB_WIDTH(12'd0), .LFB_HEIGHT(12'd0), .LFB_STRIDE(14'd0),
		.LED_USER(), .LED_POWER(), .LED_DISK(), .BUTTONS(),
		.CLK_AUDIO(1'b0), .AUDIO_L(), .AUDIO_R(), .AUDIO_S(), .AUDIO_MIX(),
		.ADC_BUS(),
		.SD_SCK(), .SD_MOSI(), .SD_MISO(1'b1), .SD_CS(), .SD_CD(1'b1),
		.DDRAM_CLK(), .DDRAM_BUSY(1'b1), .DDRAM_BURSTCNT(), .DDRAM_ADDR(), .DDRAM_DOUT(64'd0),
		.DDRAM_DOUT_READY(1'b0), .DDRAM_RD(), .DDRAM_DIN(), .DDRAM_BE(), .DDRAM_WE(),
		.SDRAM_CLK(), .SDRAM_CKE(), .SDRAM_A(), .SDRAM_BA(), .SDRAM_DQ(), .SDRAM_DQML(),
		.SDRAM_DQMH(), .SDRAM_nCS(), .SDRAM_nCAS(), .SDRAM_nRAS(), .SDRAM_nWE(),
		.UART_CTS(1'b0), .UART_RTS(), .UART_RXD(1'b1), .UART_TXD(), .UART_DTR(), .UART_DSR(1'b0),
		.USER_OUT(), .USER_IN(7'h7F),
		.OSD_STATUS(1'b0)
	);

	integer errors = 0;
	task check(input [255:0] what, input [31:0] got, input [31:0] want);
		if (got !== want) begin
			$display("FAIL: %0s = %0d, erwartet %0d", what, got, want);
			errors = errors + 1;
		end else
			$display("ok:   %0s = %0d", what, got);
	endtask

	// --- Vermessen -----------------------------------------------------------
	integer x = 0, de_cnt = 0, hs_cnt = 0, vs_clk = 0, vs_len = -1, vs_hs_sync = 0, lines = 0, de_lines = 0, vs_lines = 0;
	integer line_len = -1, line_de = -1, line_hs = -1, frame_lines = -1, frame_de = -1, frame_vs = -1;
	integer frames = 0, ce_low = 0, not_black = 0, bad = 0;
	reg     hs_old = 0, vs_old = 0, had_de = 0, had_vs = 0;
	reg [23:0] bar_px [0:7];
	integer box_seen = 0;
	integer box_out = 0;
	always @(posedge clk_video)
		if (dut.box_x > 1280 - 64 || dut.box_y > 720 - 64) box_out = box_out + 1;

	always @(posedge clk_video) if (!reset) begin
		if (!ce_pixel) ce_low = ce_low + 1;
		x = x + 1;
		if (de) begin
			de_cnt = de_cnt + 1; had_de = 1;
			if (frames == 2 && lines == 40 && de_cnt % 160 == 80) bar_px[de_cnt / 160] = {r, g, b};
			if ({r, g, b} == 24'hFFFFFF && lines > 400) box_seen = box_seen + 1;
		end else if ({r, g, b} != 24'd0) not_black = not_black + 1;
		if (hs) hs_cnt = hs_cnt + 1;
		if (vs) begin had_vs = 1; vs_clk = vs_clk + 1; end
		if (!vs && vs_old) begin vs_len = vs_clk; vs_clk = 0; end
		if (vs && !vs_old && !(hs && !hs_old)) vs_hs_sync = vs_hs_sync + 1;
		if (hs && !hs_old) begin
			if (frames >= 2 && (x != 1650 || (de_cnt != 0 && de_cnt != 1280))) bad = bad + 1;
			line_len = x; if (de_cnt) line_de = de_cnt;
			lines = lines + 1; if (had_de) de_lines = de_lines + 1; if (had_vs) vs_lines = vs_lines + 1;
			x = 0; de_cnt = 0; had_de = 0; had_vs = 0;
		end
		if (!hs && hs_old) begin line_hs = hs_cnt; hs_cnt = 0; end
		if (vs && !vs_old) begin
			if (frames >= 1) begin frame_lines = lines; frame_de = de_lines; frame_vs = vs_lines; end
			frames = frames + 1; lines = 0; de_lines = 0; vs_lines = 0;
		end
		hs_old = hs; vs_old = vs;
	end

	integer i;
	initial begin
		wait (frames == 3);
		check("Takte je Zeile", line_len, 1650);
		check("Pixel je Zeile", line_de, 1280);
		check("HS-Länge (Takte)", line_hs, 40);
		check("Zeilen je Bild", frame_lines, 750);
		check("sichtbare Zeilen", frame_de, 720);
		check("VS-Länge (Takte, 5 Zeilen)", vs_len, 5 * 1650);
		check("VS-Beginn nicht mit HS-Beginn", vs_hs_sync, 0);
		check("Zeilen mit falscher Länge", bad, 0);
		check("CE_PIXEL = 0 gesehen", ce_low, 0);
		check("Farbe außerhalb DE", not_black, 0);
		// Balken: Weiß, Gelb, Cyan, Grün, Magenta, Rot, Blau, Schwarz
		check("Balken 0 Weiß",   bar_px[0], 24'hFFFFFF);
		check("Balken 1 Gelb",   bar_px[1], 24'hFFFF00);
		check("Balken 2 Cyan",   bar_px[2], 24'h00FFFF);
		check("Balken 3 Grün",   bar_px[3], 24'h00FF00);
		check("Balken 4 Magenta",bar_px[4], 24'hFF00FF);
		check("Balken 5 Rot",    bar_px[5], 24'hFF0000);
		check("Balken 6 Blau",   bar_px[6], 24'h0000FF);
		check("Balken 7 Schwarz",bar_px[7], 24'h000000);
		// 2 Schritte (Ende Bild 0 und 1): x 1212→1208→1204 (Umkehr an der Schwelle), y 3→0→3
		check("Quadrat außerhalb (Takte)", box_out, 0);
		check("Quadrat x nach Abprallen", dut.box_x, 1204);
		check("Quadrat y nach Abprallen", dut.box_y, 3);
		check("Richtung x (0 = links)", dut.box_dx, 0);
		check("Richtung y (1 = runter)", dut.box_dy, 1);
		if (errors == 0) $display("PASS: tb_testpattern");
		else             $display("FAIL: tb_testpattern, %0d Fehler", errors);
		$finish;
	end

	initial begin
		repeat (80) #1_000_000_000;   // 80 ms
		$display("FAIL: Zeitlimit (Bilder: %0d)", frames);
		$finish;
	end

endmodule

`default_nettype wire
