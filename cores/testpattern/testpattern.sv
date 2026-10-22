// SPDX-License-Identifier: GPL-3.0-or-later
// testpattern — Testcore für den sys/-Port (P1).
//
// Zweck:  Ein MiSTer-Core in Minimalform: dieselbe Schnittstelle wie jeder
//         MiSTer-Core (module emu, Ports aus sys/emu_ports.vh, hps_io), aber
//         mit einem Bild, das ohne Scaler direkt über HDMI geht: 1280 x 720
//         bei 60 Hz (CEA-861), Pixeltakt 74,25 MHz = CLK_VIDEO, CE_PIXEL = 1.
//         Muster: Farbbalken (oben), Graustufenverlauf (unten), ein weißes
//         Quadrat wandert über das Bild — so sieht man, dass der Core läuft.
//         Über das OSD (ab P2, Main_MiSTer) wählbar: Balken / Gitter / Verlauf.
//         P3: ddr_test prüft den DDRAM-Port (F2SDRAM ins HPS-DDR) — nach dem
//         Reset und per OSD "DDR-Test starten"; Ergebnis als Feld am linken Rand
//         (grau: noch nicht gelaufen, gelb: läuft, grün: bestanden, rot: Fehler).
// Takte:  clk_sys = clk_vid = 74,25 MHz aus der eigenen PLL pll_tp (CLK_50M).
//         hps_io läuft im selben Takt.

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Nicht benutzte Ausgänge (wie im Template-Core) /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_SL      = 0;
assign VGA_F1      = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S   = 0;
assign AUDIO_L   = 0;
assign AUDIO_R   = 0;
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

assign VIDEO_ARX = 13'd16;
assign VIDEO_ARY = 13'd9;

////////////////////////////  HPS  /////////////////////////////////

`include "build_id.v"
localparam CONF_STR = {
	"Testpattern;;",
	"-;",
	"O[2:1],Muster,Farbbalken,Gitter,Verlauf;",
	"-;",
	"T[3],DDR-Test starten;",
	"-;",
	"T[0],Reset;",
	"V,v",`BUILD_DATE
};

wire   [1:0] buttons;
wire [127:0] status;
wire         clk_sys;
wire         pll_locked;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0)
);

////////////////////////////  Takt  /////////////////////////////////

pll_tp pll
(
	.refclk(CLK_50M),
	.rst(1'b0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

// locked kommt asynchron aus der PLL: erst durch zwei Flipflops (die erste
// Stufe heißt "*meta*" — dafür gibt sys_top_de25.sdc den Weg frei).
reg locked_meta_q = 1'b0, locked_q = 1'b0;
always @(posedge clk_sys) {locked_q, locked_meta_q} <= {locked_meta_q, pll_locked};

wire reset = RESET | status[0] | buttons[1] | ~locked_q;

////////////////////////////  DDR-Test  /////////////////////////////
// 128 KB ab Byte 0x3000_0000 (MiSTer-DDRAM) = physisch 0xB000_0000 im
// reservierten Fenster (sysmem_de25). Start nach dem Reset und per OSD.

reg  reset_q = 1'b1, ddr_start_q = 1'b0, trig_q = 1'b0;
wire ddr_running, ddr_done, ddr_pass;
wire [15:0] ddr_err;
wire [31:0] ddr_wr_cycles, ddr_rd_cycles;

always @(posedge clk_sys) begin
	reset_q     <= reset;
	trig_q      <= status[3];
	ddr_start_q <= (reset_q & ~reset) | (status[3] & ~trig_q);
end

assign DDRAM_CLK = clk_sys;

ddr_test ddr_test
(
	.clk(clk_sys),
	.rst(reset),
	.start(ddr_start_q),
	.ddram_addr(DDRAM_ADDR),
	.ddram_burstcnt(DDRAM_BURSTCNT),
	.ddram_busy(DDRAM_BUSY),
	.ddram_dout(DDRAM_DOUT),
	.ddram_dout_ready(DDRAM_DOUT_READY),
	.ddram_rd(DDRAM_RD),
	.ddram_din(DDRAM_DIN),
	.ddram_be(DDRAM_BE),
	.ddram_we(DDRAM_WE),
	.running_q(ddr_running),
	.done_q(ddr_done),
	.pass_q(ddr_pass),
	.err_q(ddr_err),
	.wr_cycles_q(ddr_wr_cycles),
	.rd_cycles_q(ddr_rd_cycles)
);

////////////////////////////  Bild  /////////////////////////////////
// 1280 x 720 @ 60 Hz: 1650 Takte je Zeile (1280 sichtbar, 110 vorn, 40 Sync,
// 220 hinten), 750 Zeilen (720 sichtbar, 5 vorn, 5 Sync, 20 hinten),
// Syncs high-aktiv.

localparam H_ACT = 1280, H_FP = 110, H_SYNC = 40, H_BP = 220;
localparam V_ACT = 720,  V_FP = 5,   V_SYNC = 5,  V_BP = 20;
localparam H_TOT = H_ACT + H_FP + H_SYNC + H_BP;   // 1650
localparam V_TOT = V_ACT + V_FP + V_SYNC + V_BP;   //  750

reg [10:0] hc = 0;
reg  [9:0] vc = 0;
reg [10:0] box_x = 0;
reg  [9:0] box_y = 0;
reg        box_dx = 1, box_dy = 1;

always @(posedge clk_sys) begin
	if (reset) begin
		hc <= 0;
		vc <= 0;
	end else if (hc == H_TOT - 1) begin
		hc <= 0;
		if (vc == V_TOT - 1) begin
			vc <= 0;
			// Quadrat (64 x 64) einmal pro Bild weiterschieben, an den Rändern abprallen.
			// Am Rand Richtung UND Schritt im selben Takt umdrehen — sonst läuft
			// box_x bei 0 nach -4 = 2044 über und das Quadrat bleibt hängen.
			if (box_dx ? (box_x >= H_ACT - 64 - 4) : (box_x >= 4)) box_x <= box_x - 11'd4;
			else                                                   box_x <= box_x + 11'd4;
			if (box_dy ? (box_y >= V_ACT - 64 - 3) : (box_y >= 3)) box_y <= box_y - 10'd3;
			else                                                   box_y <= box_y + 10'd3;
			if (box_dx && box_x >= H_ACT - 64 - 4) box_dx <= 0;
			if (!box_dx && box_x < 4)              box_dx <= 1;
			if (box_dy && box_y >= V_ACT - 64 - 3) box_dy <= 0;
			if (!box_dy && box_y < 3)              box_dy <= 1;
		end else begin
			vc <= vc + 1'd1;
		end
	end else begin
		hc <= hc + 1'd1;
	end
end

wire active = (hc < H_ACT) && (vc < V_ACT);
wire in_box = (hc >= box_x) && (hc < box_x + 11'd64) && (vc >= box_y) && (vc < box_y + 10'd64);

// Farbbalken: 8 Balken zu 160 Pixeln (Weiß, Gelb, Cyan, Grün, Magenta, Rot, Blau, Schwarz)
wire [2:0] bar = hc[10:0] / 11'd160;
// Rot in Balken 0,1,4,5, Grün in 0..3, Blau in 0,2,4,6 — also je ein Bit von bar.
wire [23:0] bar_rgb = { {8{~bar[1]}}, {8{~bar[2]}}, {8{~bar[0]}} };

reg [23:0] rgb;
always @(posedge clk_sys) begin
	case (status[2:1])
		2'd1:    rgb <= (hc[5:0] == 0 || vc[5:0] == 0) ? 24'hFFFFFF : 24'h202060;          // Gitter
		2'd2:    rgb <= {3{hc[10:3]}};                                                       // Verlauf
		default: rgb <= (vc < V_ACT / 2) ? bar_rgb : {3{hc[10:3]}};                         // Balken + Verlauf
	endcase
	if (in_box) rgb <= 24'hFFFFFF;
	// Ergebnis des DDR-Tests: Feld 128 x 64 am linken Rand (Zeilen 280..343,
	// unterhalb der Stelle, an der tb_testpattern die Balken prüft), weißer Rand
	if (hc < 11'd128 && vc >= 10'd280 && vc < 10'd344) begin
		if (hc < 11'd2 || hc >= 11'd126 || vc < 10'd282 || vc >= 10'd342) rgb <= 24'hFFFFFF;
		else if (ddr_running)                                          rgb <= 24'hE0E000;  // gelb
		else if (ddr_done && ddr_pass)                                 rgb <= 24'h00C000;  // grün
		else if (ddr_done)                                             rgb <= 24'hE00000;  // rot
		else                                                           rgb <= 24'h606060;  // grau
	end
end

// VS wechselt wie in CEA-861 gleichzeitig mit dem Beginn von HS.
reg hs_q, vs_q, de_q;
always @(posedge clk_sys) begin
	hs_q <= (hc >= H_ACT + H_FP) && (hc < H_ACT + H_FP + H_SYNC);
	if (hc == H_ACT + H_FP)
		vs_q <= (vc >= V_ACT + V_FP) && (vc < V_ACT + V_FP + V_SYNC);
	de_q <= active;
end

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = 1'b1;
assign VGA_HS    = hs_q;
assign VGA_VS    = vs_q;
assign VGA_DE    = de_q;
assign {VGA_R, VGA_G, VGA_B} = de_q ? rgb : 24'd0;

// Lebenszeichen: LED_USER blinkt mit ~1 Hz (74,25 MHz / 2^26)
reg [25:0] blink = 0;
always @(posedge clk_sys) blink <= blink + 1'd1;
assign LED_USER = blink[25];

endmodule
