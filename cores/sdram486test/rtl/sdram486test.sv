//============================================================================
//
//  SDRAM-Test für den z486-Controller (Retro25, P5 Z3).
//  Abgeleitet von MiSTers MemTest (memtest.sv):
//  Copyright (C) 2017-2019 Sorgelig
//  Retro25-Änderungen 2026: tester486 (z486-sdram.v) statt tester, feste
//  PLL 85 MHz, keine Frequenzumschaltung.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================
//
// Anzeige (wie MemTest): oben Laufzeit in Minuten und die Phase von
// SDRAM_CLK in Grad (Makro PHASE_BCD), Mitte Durchläufe (hex), unten Fehler
// (hex). Ein Durchlauf = 128 MB schreiben, Bytes über DQM schreiben, lesen.
// Takte: clk_ram 85 MHz (Controller), clk_sdram = 85 MHz mit Phase (Revision
// wählt die PLL), CLK_50M für Laufzeit, 27 MHz Video.

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VIDEO_ARX = 0;
assign VIDEO_ARY = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 0;
assign AUDIO_L = 0;
assign AUDIO_R = 0;
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = 0;
assign BUTTONS   = 0;

`ifndef PHASE_BCD
`define PHASE_BCD 16'hF000
`endif

wire [31:0] status;
wire  [1:0] buttons;

`include "build_id.v"
localparam CONF_STR =
{
	"SDRAM486;;",
	"R0,Reset Test;",
	"V,v",`BUILD_DATE
};

wire        scandoubler;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(CLK_50M),
	.HPS_BUS(HPS_BUS),

	.status(status),
	.buttons(buttons),
	.forced_scandoubler(scandoubler),
	.ps2_kbd_led_use(0),
	.ps2_kbd_led_status(0)
);

///////////////////////////////////////////////////////////////////
// Takte: feste PLL (Revision wählt die Phase von clk_sdram), SDRAM_CLK über
// das DDIO-Register im I/O-Block (din 2'b10: Takt 1:1), wie MemTest/C64
wire clk_ram, clk_sdram, locked;

pll_486 pll
(
	.refclk(CLK_50M),
	.rst(RESET),
	.outclk_0(clk_ram),
	.outclk_1(clk_sdram),
	.locked(locked)
);

sdram_clk_ddio sdramclk_ddr
(
	.ck(clk_sdram),
	.din(2'b10),
	.pad_out(SDRAM_CLK)
);

assign SDRAM_CKE = 1;

///////////////////////////////////////////////////////////////////
// Laufzeit in Minuten (BCD), wie MemTest. Register mit Startwert auf
// Modulebene (Quartus-Pro-Falle 16754).
reg [15:0] mins = 0;
integer    min = 0;

always @(posedge CLK_50M) begin
	if (status[0] | buttons[1]) begin
		min  <= 0;
		mins <= 0;
	end else begin
		min <= min + 1;
		if (min == 2999999999) begin
			min <= 0;
			if (mins[3:0] < 9) mins[3:0] <= mins[3:0] + 1'd1;
			else begin
				mins[3:0] <= 0;
				if (mins[7:4] < 9) mins[7:4] <= mins[7:4] + 1'd1;
				else begin
					mins[7:4] <= 0;
					if (mins[11:8] < 9) mins[11:8] <= mins[11:8] + 1'd1;
					else begin
						mins[11:8] <= 0;
						if (mins[15:12] < 9) mins[15:12] <= mins[15:12] + 1'd1;
						else mins[15:12] <= 0;
					end
				end
			end
		end
	end
end

///////////////////////////////////////////////////////////////////
// Reset des Testers: nach PLL-Lock, nach Reset und per OSD "Reset Test"
reg     reset = 1;
integer timeout = 0;
always @(posedge clk_ram) begin
	if (timeout) timeout <= timeout - 1;
	reset <= |timeout;
	if (~locked && (timeout < 1000000)) timeout <= 1000000;
	if (RESET | status[0] | buttons[1]) timeout <= 1000000;
end

wire [31:0] passcount, failcount;
tester486 #(.FREQ(85_000_000)) my_memtst
(
	.clk(clk_ram),
	.rst_n(~reset),
	.sz(2'd3),
	.chip(2'd0),
	.passcount(passcount),
	.failcount(failcount),
	.DRAM_DQ(SDRAM_DQ),
	.DRAM_ADDR(SDRAM_A),
	.DRAM_LDQM(SDRAM_DQML),
	.DRAM_UDQM(SDRAM_DQMH),
	.DRAM_WE_N(SDRAM_nWE),
	.DRAM_CS_N(SDRAM_nCS),
	.DRAM_RAS_N(SDRAM_nRAS),
	.DRAM_CAS_N(SDRAM_nCAS),
	.DRAM_BA_0(SDRAM_BA[0]),
	.DRAM_BA_1(SDRAM_BA[1])
);

///////////////////////////////////////////////////////////////////
wire videoclk;

pll_memtest_vid vpll
(
	.refclk(CLK_50M),
	.rst(1'b0),
	.outclk_0(videoclk)
);

assign CLK_VIDEO = videoclk;

wire [1:0] b, r, g;
vgaout showrez
(
	.clk(videoclk),
	.scandoubler(scandoubler),
	.rez1({2'd3, passcount[27:0]}),
	.rez2(failcount),
	.rez3(2'b00),
	.bg(6'b000001),
	.freq(`PHASE_BCD),
	.elapsed(mins),
	.mark(8'h00),
	.ce(CE_PIXEL),
	.hs(VGA_HS),
	.vs(VGA_VS),
	.de(VGA_DE),
	.b(b),
	.r(r),
	.g(g)
);

assign VGA_B  = {4{b}};
assign VGA_R  = {4{r}};
assign VGA_G  = {4{g}};

endmodule
