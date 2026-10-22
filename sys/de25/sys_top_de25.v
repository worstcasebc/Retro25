//============================================================================
//
//  MiSTer hardware abstraction module
//  (c)2017-2020 Alexey Melnikov
//
//  DE25-Nano-Fassung (Retro25), 2026: abgeleitet von
//  sys/vendor/mister/sys_top.v (Template_MiSTer 9c8eadb). Änderungen sind mit
//  "DE25:" markiert; Überblick in sys/de25/README.md.
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
//
//============================================================================

// DE25: Stand P3. Scaler (ascal), HDMI-PLL zur Laufzeit umstellbar
// (pll_cfg_de25), HDMI-Sender über Main (i2c_master_de25);
// MISTER_DEBUG_NOHDMI (Direktvideo ohne Scaler, P1) geht weiterhin.
// MISTER_DISABLE_ALSA und MISTER_DISABLE_YC sind Pflicht; ohne sie bricht
// die Übersetzung ab (siehe unten "noch nicht portiert").
`ifndef MISTER_DISABLE_ALSA
	DE25_ALSA_noch_nicht_portiert__MISTER_DISABLE_ALSA_setzen de25_todo_alsa();
`endif
`ifdef MISTER_DUAL_SDRAM
	DE25_hat_kein_zweites_SDRAM de25_todo_sdram2();
`endif

module sys_top_de25
(
	/////////// CLOCK //////////
	// DE25: drei 50-MHz-Eingänge wie beim DE10-Nano (Zuordnung unten)
	input         CLOCK0_50,
	input         CLOCK1_50,
	input         CLOCK2_50,

	//////////// HDMI //////////
	inout         HDMI_I2C_SCL,   // DE25: inout, damit i2c_master_de25 SCL zurücklesen kann
	inout         HDMI_I2C_SDA,

	output        HDMI_MCLK,
	output        HDMI_SCLK,
	output        HDMI_LRCLK,
	output        HDMI_I2S,

	output        HDMI_TX_CLK,
	output        HDMI_TX_DE,
	output [23:0] HDMI_TX_D,
	output        HDMI_TX_HS,
	output        HDMI_TX_VS,

	input         HDMI_TX_INT,

	//////////// SDR ///////////
	// DE25: SDRAM auf dem Board (128 MB, zwei Chip-Selects)
	output [12:0] SDRAM_A,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nWE,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nCS,
	output        SDRAM_nCS2,
	output  [1:0] SDRAM_BA,
	output        SDRAM_CLK,
	output        SDRAM_CKE,

	////////// MB KEY ///////////
	input   [1:0] KEY,

	////////// MB SWITCH ////////
	input   [3:0] SW,

	////////// MB LED ///////////
	// DE25: LEDs sind low-aktiv
	output  [7:0] LEDR,

	////////// HPS (DE25) ///////
	// Speicher des HPS (über Pins des FPGA)
	input         LPDDR4A_REFCLK_p,
	output        LPDDR4A_CS_n,
	output  [5:0] LPDDR4A_CA,
	output        LPDDR4A_CK,
	output        LPDDR4A_CKE,
	output        LPDDR4A_CK_n,
	inout   [3:0] LPDDR4A_DM,
	inout  [31:0] LPDDR4A_DQ,
	inout   [3:0] LPDDR4A_DQS,
	inout   [3:0] LPDDR4A_DQS_n,
	output        LPDDR4A_RESET_n,
	input         LPDDR4A_RZQ,

	// Anschlüsse des HPS
	input         HPS_CLK_25,
	output        HPS_ENET_MDC,
	inout         HPS_ENET_MDIO,
	input         HPS_ENET_RX_CLK,
	input         HPS_ENET_RX_CTL,
	input   [3:0] HPS_ENET_RX_DATA,
	output        HPS_ENET_TX_CLK,
	output        HPS_ENET_TX_CTL,
	output  [3:0] HPS_ENET_TX_DATA,
	inout         HPS_GSENSOR_I2C_EN,
	inout         HPS_GSENSOR_INT,
	inout         HPS_I2C_SCL,
	inout         HPS_I2C_SDA,
	inout         HPS_KEY,
	inout         HPS_LED,
	output        HPS_SD_CLK,
	inout         HPS_SD_CMD,
	inout   [3:0] HPS_SD_DATA,
	input         HPS_UART_RX,
	output        HPS_UART_TX,
	input         HPS_USB_CLK,
	inout   [7:0] HPS_USB_DATA,
	input         HPS_USB_DIR,
	input         HPS_USB_NXT,
	output        HPS_USB_STP
);

// DE25: Takte wie beim DE10-Nano benannt. CLOCK2_50 speist außerdem die PLL
// des HPS-Systems (clk_100).
wire FPGA_CLK1_50 = CLOCK0_50;
wire FPGA_CLK2_50 = CLOCK2_50;
wire FPGA_CLK3_50 = CLOCK1_50;

//////////////////////  Secondary SD  ///////////////////////////////////
// DE25: kein zweites SD-Laufwerk am FPGA.
wire SD_CS, SD_CLK, SD_MOSI, SD_MISO, SD_CD;
assign SD_CD   = 1'b1;
assign SD_MISO = 1'b1;

//////////////////////  LEDs/Buttons  ///////////////////////////////////

reg [7:0] led_overtake = 0;
reg [7:0] led_state    = 0;

wire led_p =  led_power[1] ? ~led_power[0] : 1'b0;
wire led_d =  led_disk[1]  ? ~led_disk[0]  : ~(led_disk[0] | gp_out[29]);
wire led_u = ~led_user;
wire led_locked;

//LEDs on de10-nano board
// DE25: gleiche Belegung, LEDs aber low-aktiv
assign LEDR = ~((led_overtake & led_state) | (~led_overtake & {1'b0,led_locked,1'b0, ~led_p, 1'b0, ~led_d, 1'b0, ~led_u}));

// DE25: kein MiSTer-I/O-Board (MCP23009)
wire [2:0] mcp_btn  = 3'b000;
wire       mcp_sdcd = 1'b1;
wire       mcp_en   = 1'b0;
wire       mcp_mode = 1'b0;

wire io_dig = mcp_en ? mcp_mode : SW[3];

// DE25: keine Tasten des Analog-Boards
wire   BTN_RESET = 1'b1;
wire   BTN_OSD   = 1'b1;
wire   BTN_USER  = 1'b1;
wire   BTN_DIS   = 1'b1;

reg BTN_EN = 0;
reg [25:0] btn_timeout = 0;
initial btn_timeout = 0;
// DE25 (Quartus Pro): lokale Register ohne Startwert — mit Startwert meldet
// Pro Warnung 16754 ("should be declared as automatic or static"); so sind sie
// eindeutig statisch wie unter Quartus Standard (Einschaltwert ohnehin 0).
always @(posedge FPGA_CLK2_50) begin
	reg btn_up;
	reg btn_en;

	btn_up <= BTN_RESET & BTN_OSD & BTN_USER;
	if(~reset & btn_up & ~&btn_timeout) btn_timeout <= btn_timeout + 1'd1;
	btn_en <= ~BTN_DIS;
	BTN_EN <= &btn_timeout & btn_en;
end

wire btn_r = (mcp_en | SW[3]) ? mcp_btn[1] : (BTN_EN & ~BTN_RESET);
wire btn_o = (mcp_en | SW[3]) ? mcp_btn[2] : (BTN_EN & ~BTN_OSD  );
wire btn_u = (mcp_en | SW[3]) ? mcp_btn[0] : (BTN_EN & ~BTN_USER );

reg btn_user, btn_osd;
always @(posedge FPGA_CLK2_50) begin
	integer div;
	reg [7:0] deb_user;
	reg [7:0] deb_osd;

	div <= div + 1'b1;
	if(div > 100000) div <= 0;

	if(!div) begin
		deb_user <= {deb_user[6:0], btn_u | ~KEY[1]};
		if(&deb_user) btn_user <= 1;
		if(!deb_user) btn_user <= 0;

		deb_osd <= {deb_osd[6:0], btn_o | ~KEY[0]};
		if(&deb_osd) btn_osd <= 1;
		if(!deb_osd) btn_osd <= 0;
	end
end

/////////////////////////  HPS I/O  /////////////////////////////////////

// gp_in[31] = 0 - quick flag that FPGA is initialized (HPS reads 1 when FPGA is not in user mode)
//                 used to avoid lockups while JTAG loading
wire [31:0] gp_in = {1'b0, btn_user | btn[1], btn_osd | btn[0], io_dig, 7'd0, ~HDMI_TX_INT, io_ver, io_ack, io_wide, io_dout | io_dout_sys};
wire [31:0] gp_out;

wire  [1:0] io_ver = 1; // 0 - obsolete. 1 - optimized HPS I/O. 2,3 - reserved for future.
wire        io_wait;
wire        io_wide;
wire [15:0] io_dout;
wire [15:0] io_din = gp_outr[15:0];
wire        io_clk = gp_outr[17];
wire        io_ss0 = gp_outr[18];
wire        io_ss1 = gp_outr[19];
wire        io_ss2 = gp_outr[20];

`ifndef MISTER_DEBUG_NOHDMI
	wire io_osd_hdmi = io_ss1 & ~io_ss0;
`endif

wire io_fpga     = ~io_ss1 & io_ss0;
wire io_uio      = ~io_ss1 & io_ss2;

reg  io_ack;
reg  rack;
wire io_strobe = ~rack & io_clk;

always @(posedge clk_sys) begin
	if(~(io_wait | vs_wait) | io_strobe) begin
		rack <= io_clk;
		io_ack <= rack;
	end
end

reg [31:0] gp_outr;
always @(posedge clk_sys) begin
	reg [31:0] gp_outd;
	gp_outr <= gp_outd;
	gp_outd <= gp_out;
end

`ifdef MISTER_DUAL_SDRAM
	wire  [7:0] core_type  = 'hA8; // generic core, dual SDRAM.
`else
	wire  [7:0] core_type  = 'hA4; // generic core.
`endif

// HPS will not communicate to core if magic is different
wire [31:0] core_magic = {24'h5CA623, core_type};

// DE25: Ersatz für cyclonev_hps_interface_mpu_general_purpose — Register an
// der LW-Bridge (Linux: 0x2001_0100), siehe sys/de25/hps_gp_bridge.v.
hps_gp_bridge h2f_gp
(
	.clk_av(clk_100),
	.rst_av(rst_av),
	.avs_address(gp_m0_address[3:2]),
	.avs_write(gp_m0_write),
	.avs_writedata(gp_m0_writedata),
	.avs_byteenable(gp_m0_byteenable),
	.avs_read(gp_m0_read),
	.avs_readdata(gp_m0_readdata),
	.avs_readdatavalid(gp_m0_readdatavalid),
	.avs_waitrequest(gp_m0_waitrequest),

	.clk_sys(clk_sys),
	.gp_in({~gp_out[31] ? core_magic : gp_in}),
	.gp_out(gp_out)
);


reg [15:0] cfg;
reg        cfg_set      = 0;

`ifdef MISTER_DEBUG_NOHDMI
	wire    vga_fb       = 0;
	wire    direct_video = 1;
`else
	wire    vga_fb       = cfg[12] | vga_force_scaler;
	wire    direct_video = cfg[10];
`endif

wire       audio_96k    = cfg[6];
wire       csync_en     = cfg[3];
wire       io_osd_vga   = io_ss1 & ~io_ss2;
`ifndef MISTER_DUAL_SDRAM
	wire forced_scandoubler = cfg[4];
	wire ypbpr_en           = cfg[5];
	wire sog                = cfg[9];
	`ifdef MISTER_DEBUG_NOHDMI
		wire vga_scaler   = 0;
	`else
		wire vga_scaler   = cfg[2] | vga_force_scaler;
	`endif
`endif

reg        cfg_custom_t = 0;
reg  [5:0] cfg_custom_p1;
reg [31:0] cfg_custom_p2;

reg  [4:0] vol_att;
initial vol_att = 5'b11111;
reg  [1:0] vol_boost = 0;

reg  [11:0] coef_addr;
reg  [9:0] coef_data;
reg        coef_wr = 0;

wire[12:0] ARX, ARY;
reg [11:0] VSET = 0, HSET = 0;
reg        FREESCALE = 0;
reg  [2:0] scaler_flt;
reg        lowlat = 0;
reg        cfg_done = 0;

reg        vs_wait = 0;
reg [11:0] vs_line = 0;

reg        scaler_out = 0;
reg        vrr_mode = 0;
wire       hdmi_blackout;

reg [31:0] aflt_rate = 7056000;
reg [39:0] acx  = 4258969;
reg  [7:0] acx0 = 3;
reg  [7:0] acx1 = 3;
reg  [7:0] acx2 = 1;
reg [23:0] acy0 = -24'd6216759;
reg [23:0] acy1 =  24'd6143386;
reg [23:0] acy2 = -24'd2023767;
reg        areset = 0;
reg [12:0] arc1x = 0;
reg [12:0] arc1y = 0;
reg [12:0] arc2x = 0;
reg [12:0] arc2y = 0;
reg [15:0] io_dout_sys;
// DE25: Schattenkopie der Core-Palette (8bpp-Framebuffer) für Mains Screenshot,
// gelesen über UIO 0x4E (RAM weiter unten bei den fb_pal_*-Leitungen)
reg  [7:0] fbpal_ra;
reg [23:0] fbpal_q;
reg [15:0] fbpal_wcnt;   // Anzahl Paletten-Schreibzugriffe (Antwort auf 0x4E)

// DE25: cnt ohne Startwert (Quartus Pro, Warnung 16754, siehe oben); dbg_*
// zeigen den Parser in video_debug (Fehlersuche Befehl 0x20).
reg  [7:0] dbg_cmd = 0, dbg_cnt = 0, dbg_strobes = 0, dbg_cmd20 = 0;
always@(posedge clk_sys) begin
	reg  [7:0] cmd;
	reg        has_cmd;
	reg  [7:0] cnt;
	reg        vs_d0,vs_d1,vs_d2;
	reg  [4:0] acx_att;
	reg  [7:0] fb_crc;
	reg  [1:0] sl_r;

	coef_wr <= 0;
	sl_r <= FB_EN ? 2'b00 : scanlines;

`ifndef MISTER_DEBUG_NOHDMI
	shadowmask_wr <= 0;
`endif

	if(~io_uio) begin
		has_cmd <= 0;
		cmd <= 0;
		areset <= 0;
		acx_att <= 0;
		acx <= acx >> acx_att;
		io_dout_sys <= 0;
	end
	else
	if(io_strobe) begin
		io_dout_sys <= 0;
		dbg_strobes <= dbg_strobes + 1'd1;
		dbg_cmd <= has_cmd ? cmd : io_din[7:0];
		dbg_cnt <= has_cmd ? cnt + 1'd1 : 8'd0;
		if(!has_cmd && io_din[7:0] == 'h20) dbg_cmd20 <= dbg_cmd20 + 1'd1;
		if(!has_cmd) begin
			has_cmd <= 1;
			cmd <= io_din[7:0];
			cnt <= 0;
			if(io_din[7:0] == 'h30) vs_wait <= 1;
			if(io_din[7:0] == 'h39) begin
				aflt_rate <= 7056000;
				acx  <= 4258969;
				acx0 <= 3;
				acx1 <= 3;
				acx2 <= 1;
				acy0 <= -24'd6216759;
				acy1 <=  24'd6143386;
				acy2 <= -24'd2023767;
				areset <= 1;
				io_dout_sys <= 'b11;
			end
			if(io_din[7:0] == 'h20) io_dout_sys <= 'b11;
`ifdef MISTER_DISABLE_ADAPTIVE
			if(io_din[7:0] == 'h2B) io_dout_sys <= {fb_en, sl_r, 4'b0110};
`else
			if(io_din[7:0] == 'h2B) io_dout_sys <= {fb_en, sl_r, 4'b0111};
`endif
			if(io_din[7:0] == 'h2F) io_dout_sys <= 1;
			if(io_din[7:0] == 'h3E) io_dout_sys <= 1;
`ifndef MISTER_DEBUG_NOHDMI
			if(io_din[7:0] == 'h40) io_dout_sys <= fb_crc;
`endif
			if(io_din[7:0] == 'h42) io_dout_sys <= {1'b1, frame_cnt};
			if(io_din[7:0] == 'h44) io_dout_sys <= 1;
			// DE25: 0x4E = Core-Palette lesen (je Eintrag 2 Wörter: G/B, dann R)
			if(io_din[7:0] == 'h4E) begin
				fbpal_ra <= 0;
				io_dout_sys <= fbpal_wcnt | 16'h8000;
			end
		end
		else begin
			cnt <= cnt + 1'd1;
			if(cmd == 1) begin
				cfg <= io_din;
				cfg_set <= 1;
				scaler_out <= 1;
			end
			if(cmd == 'h20) begin
				cfg_set <= 0;
				if(cnt<8) begin
					case(cnt[2:0])
						0: {HDMI_PR,vrr_mode,WIDTH} <= {io_din[15:14], io_din[11:0]};
						1: HFP    <= io_din[11:0];
						2: HS     <= {io_din[15], io_din[11:0]};
						3: HBP    <= io_din[11:0];
						4: HEIGHT <= io_din[11:0];
						5: VFP    <= io_din[11:0];
						6: VS     <= {io_din[15],io_din[11:0]};
						7: VBP    <= io_din[11:0];
					endcase
`ifndef MISTER_DEBUG_NOHDMI
					if(cnt == 1) begin
						cfg_custom_p1 <= 0;
						cfg_custom_p2 <= 0;
						cfg_custom_t <= ~cfg_custom_t;
					end
				end
				else begin
					if(cnt[1:0]==0) cfg_custom_p1 <= io_din[5:0];
					if(cnt[1:0]==1) cfg_custom_p2[15:0]  <= io_din;
					if(cnt[1:0]==2) begin
						cfg_custom_p2[31:16] <= io_din;
						cfg_custom_t <= ~cfg_custom_t;
						cnt[2:0] <= 3'b100;
					end
					if(cnt == 8) {lowlat,cfg_done} <= {io_din[15],1'b1};
`endif
				end
			end
			if(cmd == 'h2F) begin
				case(cnt[3:0])
					0: {LFB_EN,LFB_FLT,LFB_FMT} <= {io_din[15], io_din[14], io_din[5:0]};
					1: LFB_BASE[15:0]  <= io_din[15:0];
					2: LFB_BASE[31:16] <= io_din[15:0];
					3: LFB_WIDTH       <= io_din[11:0];
					4: LFB_HEIGHT      <= io_din[11:0];
					5: LFB_HMIN        <= io_din[11:0];
					6: LFB_HMAX        <= io_din[11:0];
					7: LFB_VMIN        <= io_din[11:0];
					8: LFB_VMAX        <= io_din[11:0];
					9: LFB_STRIDE      <= io_din[13:0];
				endcase
			end
			if(cmd == 'h4E) begin
				io_dout_sys <= cnt[0] ? {8'h00, fbpal_q[23:16]} : fbpal_q[15:0];
				if(cnt[0]) fbpal_ra <= fbpal_ra + 1'd1;
			end
			if(cmd == 'h25) {led_overtake, led_state} <= io_din;
			if(cmd == 'h26) vol_att <= io_din[4:0];
			if(cmd == 'h27) VSET <= io_din[11:0];
			if(cmd == 'h2A) begin
				if(cnt[0]) {coef_wr,coef_data} <= {1'b1,io_din[9:0]};
				else coef_addr <= io_din[11:0];
			end
			if(cmd == 'h2B) scaler_flt <= io_din[2:0];
			if(cmd == 'h37) {FREESCALE,HSET} <= {io_din[15],io_din[11:0]};
			if(cmd == 'h38) vs_line <= io_din[11:0];
			if(cmd == 'h39) begin
				case(cnt[3:0])
					 0: {vol_boost,acx_att} <= io_din[6:0];
					 1: aflt_rate[15:0]  <= io_din;
					 2: aflt_rate[31:16] <= io_din;
					 3: acx[15:0]        <= io_din;
					 4: acx[31:16]       <= io_din;
					 5: acx[39:32]       <= io_din[7:0];
					 6: acx0             <= io_din[7:0];
					 7: acx1             <= io_din[7:0];
					 8: acx2             <= io_din[7:0];
					 9: acy0[15:0]       <= io_din;
					10: acy0[23:16]      <= io_din[7:0];
					11: acy1[15:0]       <= io_din;
					12: acy1[23:16]      <= io_din[7:0];
					13: acy2[15:0]       <= io_din;
					14: acy2[23:16]      <= io_din[7:0];
				endcase
			end
			if(cmd == 'h3A) begin
				case(cnt[3:0])
					 0: arc1x <= io_din[12:0];
					 1: arc1y <= io_din[12:0];
					 2: arc2x <= io_din[12:0];
					 3: arc2y <= io_din[12:0];
				endcase
			end
`ifndef MISTER_DEBUG_NOHDMI
			if(cmd == 'h3E) {shadowmask_wr,shadowmask_data} <= {1'b1, io_din};
			if(cmd == 'h40) begin
				case(cnt[3:0])
					0: io_dout_sys <= {arxy, arx};
					1: io_dout_sys <= {arxy, ary};
					2: io_dout_sys <= {LFB_EN, FB_EN, FB_FMT};
					3: io_dout_sys <= FB_WIDTH;
					4: io_dout_sys <= FB_HEIGHT;
					5: io_dout_sys <= FB_BASE[15:0];
					6: io_dout_sys <= FB_BASE[31:16];
					7: io_dout_sys <= FB_STRIDE;
				endcase
			end
`endif
			if(cmd == 'h41) begin
				case(cnt[3:0])
`ifndef MISTER_DISABLE_YC
					0: {pal_en,cvbs,yc_en}    <= io_din[2:0];
					4: ColorBurst_Range[15:0] <= io_din;
					5: ColorBurst_Range[16]   <= io_din[0];
`endif
					// Subcarrier commands (independent of YC module)
					1: PhaseInc[15:0]         <= io_din;
					2: PhaseInc[31:16]        <= io_din;
					3: PhaseInc[39:32]        <= io_din[7:0];
`ifndef MISTER_DUAL_SDRAM
					6: subcarrier             <= io_din[0];
`endif
				endcase
			end
		end
	end

`ifndef MISTER_DEBUG_NOHDMI
	fb_crc <= {LFB_EN, FB_EN, FB_FMT}
				^ FB_WIDTH[7:0]  ^ FB_WIDTH[11:8] 
				^ FB_HEIGHT[7:0] ^ FB_HEIGHT[11:8] 
				^ arx[7:0] ^ arx[11:8] ^ arxy
				^ ary[7:0] ^ ary[11:8];
`endif

	vs_d0 <= HDMI_TX_VS;
	if(vs_d0 == HDMI_TX_VS) vs_d1 <= vs_d0;

	vs_d2 <= vs_d1;
	if(~vs_d2 & vs_d1) vs_wait <= 0;
end

reg [7:0] frame_cnt;
always @(posedge clk_sys) begin
	reg vs_r, vs_old;
	
	vs_r <= vs_fix;
	if(vs_r == vs_fix) vs_old <= vs_r;
	if(~vs_old & vs_r) frame_cnt <= frame_cnt + 1'd1;
end

// DE25: HPS-UART und Interrupts zum HPS sind noch nicht angeschlossen
// (Leitungen unten bei "User module connection" fest belegt).

///////////////////////////  RESET  ///////////////////////////////////

reg reset_req = 0;
always @(posedge FPGA_CLK2_50) begin
	reg [1:0] resetd, resetd2;
	reg       old_reset;

	//latch the reset
	old_reset <= reset;
	if(~old_reset & reset) reset_req <= 1;

	//special combination to set/clear the reset
	//preventing of accidental reset control
	if(resetd==1) reset_req <= 1;
	if(resetd==2 && resetd2==0) reset_req <= 0;

	resetd  <= gp_out[31:30];
	resetd2 <= resetd;
end

////////////////////  SYSTEM MEMORY & SCALER  /////////////////////////

wire reset;
wire clk_100m;

// DE25: Verbindung sysmem_de25 <-> qsys_top (P3)
wire         f2s_ram1_clk, f2s_ram2_clk, f2s_vbuf_clk;
wire  [31:0] f2s_ram1_address, f2s_ram2_address, f2s_vbuf_address;
wire   [7:0] f2s_ram1_burstcount, f2s_ram2_burstcount, f2s_vbuf_burstcount;
wire         f2s_ram1_waitrequest, f2s_ram2_waitrequest, f2s_vbuf_waitrequest;
wire  [63:0] f2s_ram1_readdata, f2s_ram2_readdata;
wire [127:0] f2s_vbuf_readdata;
wire         f2s_ram1_readdatavalid, f2s_ram2_readdatavalid, f2s_vbuf_readdatavalid;
wire         f2s_ram1_read, f2s_ram2_read, f2s_vbuf_read;
wire  [63:0] f2s_ram1_writedata, f2s_ram2_writedata;
wire [127:0] f2s_vbuf_writedata;
wire   [7:0] f2s_ram1_byteenable, f2s_ram2_byteenable;
wire  [15:0] f2s_vbuf_byteenable;
wire         f2s_ram1_write, f2s_ram2_write, f2s_vbuf_write;

// DE25: DDR-Sperre vor dem Umladen (Register weiter unten bei disk_m0 + 0x3000)
reg        f2s_halt_q;
wire [2:0] f2s_halt_idle;

// DE25: Ersatz für sysmem_lite, siehe sys/de25/sysmem_de25.v
sysmem_de25 sysmem
(
	.clk_100_in(clk_100),
	.hps_ninit_done(ninit_done),

	//Reset/Clock
	.reset_core_req(reset_req),
	.reset_out(reset),

	// DE25: DDR-Ports vor dem Umladen anhalten (Register disk_m0 + 0x3000)
	.halt_req(f2s_halt_q),
	.halt_idle(f2s_halt_idle),
	.clock(clk_100m),

	//DE10-nano has no reset signal on GPIO, so core has to emulate cold reset button.
	.reset_hps_cold_req(btn_r),

	//64-bit DDR3 RAM access
	.ram1_clk(ram_clk),
	.ram1_address(ram_address),
	.ram1_burstcount(ram_burstcount),
	.ram1_waitrequest(ram_waitrequest),
	.ram1_readdata(ram_readdata),
	.ram1_readdatavalid(ram_readdatavalid),
	.ram1_read(ram_read),
	.ram1_writedata(ram_writedata),
	.ram1_byteenable(ram_byteenable),
	.ram1_write(ram_write),

	//64-bit DDR3 RAM access
	.ram2_clk(clk_audio),
	.ram2_address(ram2_address),
	.ram2_burstcount(ram2_burstcount),
	.ram2_waitrequest(ram2_waitrequest),
	.ram2_readdata(ram2_readdata),
	.ram2_readdatavalid(ram2_readdatavalid),
	.ram2_read(ram2_read),
	.ram2_writedata(ram2_writedata),
	.ram2_byteenable(ram2_byteenable),
	.ram2_write(ram2_write),

	//128-bit DDR3 RAM access
	// HDMI frame buffer
	.vbuf_clk(clk_100m),
	.vbuf_address(vbuf_address),
	.vbuf_burstcount(vbuf_burstcount),
	.vbuf_waitrequest(vbuf_waitrequest),
	.vbuf_writedata(vbuf_writedata),
	.vbuf_byteenable(vbuf_byteenable),
	.vbuf_write(vbuf_write),
	.vbuf_readdata(vbuf_readdata),
	.vbuf_readdatavalid(vbuf_readdatavalid),
	.vbuf_read(vbuf_read),

	// DE25: die drei Ports als Avalon-Master an qsys_top (F2SDRAM)
	.f2s_ram1_clk(f2s_ram1_clk),
	.f2s_ram1_address(f2s_ram1_address),
	.f2s_ram1_burstcount(f2s_ram1_burstcount),
	.f2s_ram1_waitrequest(f2s_ram1_waitrequest),
	.f2s_ram1_readdata(f2s_ram1_readdata),
	.f2s_ram1_readdatavalid(f2s_ram1_readdatavalid),
	.f2s_ram1_read(f2s_ram1_read),
	.f2s_ram1_writedata(f2s_ram1_writedata),
	.f2s_ram1_byteenable(f2s_ram1_byteenable),
	.f2s_ram1_write(f2s_ram1_write),

	.f2s_ram2_clk(f2s_ram2_clk),
	.f2s_ram2_address(f2s_ram2_address),
	.f2s_ram2_burstcount(f2s_ram2_burstcount),
	.f2s_ram2_waitrequest(f2s_ram2_waitrequest),
	.f2s_ram2_readdata(f2s_ram2_readdata),
	.f2s_ram2_readdatavalid(f2s_ram2_readdatavalid),
	.f2s_ram2_read(f2s_ram2_read),
	.f2s_ram2_writedata(f2s_ram2_writedata),
	.f2s_ram2_byteenable(f2s_ram2_byteenable),
	.f2s_ram2_write(f2s_ram2_write),

	.f2s_vbuf_clk(f2s_vbuf_clk),
	.f2s_vbuf_address(f2s_vbuf_address),
	.f2s_vbuf_burstcount(f2s_vbuf_burstcount),
	.f2s_vbuf_waitrequest(f2s_vbuf_waitrequest),
	.f2s_vbuf_readdata(f2s_vbuf_readdata),
	.f2s_vbuf_readdatavalid(f2s_vbuf_readdatavalid),
	.f2s_vbuf_read(f2s_vbuf_read),
	.f2s_vbuf_writedata(f2s_vbuf_writedata),
	.f2s_vbuf_byteenable(f2s_vbuf_byteenable),
	.f2s_vbuf_write(f2s_vbuf_write)
);


wire [28:0] ram2_address;
wire  [7:0] ram2_burstcount;
wire  [7:0] ram2_byteenable;
wire        ram2_waitrequest;
wire [63:0] ram2_readdata;
wire [63:0] ram2_writedata;
wire        ram2_readdatavalid;
wire        ram2_read;
wire        ram2_write;
wire  [7:0] ram2_bcnt;

// DE25: Palettensignale vor ihrer ersten Verwendung deklariert (ddr_svc, ascal).
// Bei MiSTer stehen sie weiter unten als "wire x = ...". Quartus Pro legt bei
// der ersten Verwendung ein implizites Netz an und verwirft die spätere
// Zuweisung (Warnungen 16746/16788) — pal_d/pal_a waren ohne Treiber.
wire [63:0] pal_data;
wire [47:0] pal_d;
wire  [6:0] pal_a;
wire        pal_wr;

// DE25: ddr_svc liest Paletten (Scaler) und ALSA-Ton aus dem DDR. Beides gibt
// es in P1 nicht (MISTER_DEBUG_NOHDMI, MISTER_DISABLE_ALSA); ddr_svc.sv braucht
// für Quartus Pro außerdem eine Anpassung (P3).
`ifndef MISTER_DEBUG_NOHDMI
ddr_svc ddr_svc
(
	.clk(clk_audio),

	.ram_waitrequest(ram2_waitrequest),
	.ram_burstcnt(ram2_burstcount),
	.ram_addr(ram2_address),
	.ram_readdata(ram2_readdata),
	.ram_read_ready(ram2_readdatavalid),
	.ram_read(ram2_read),
	.ram_writedata(ram2_writedata),
	.ram_byteenable(ram2_byteenable),
	.ram_write(ram2_write),
	.ram_bcnt(ram2_bcnt),

`ifndef MISTER_DISABLE_ALSA
	.ch0_addr(alsa_address),
	.ch0_burst(1),
	.ch0_data(alsa_readdata),
	.ch0_req(alsa_req),
	.ch0_ready(alsa_ready),
`endif

	.ch1_addr(pal_addr),
	.ch1_burst(128),
	.ch1_data(pal_data),
	.ch1_req(pal_req),
	.ch1_ready(pal_wr)
);
`else
	assign ram2_burstcount = 8'd0;
	assign ram2_address    = 29'd0;
	assign ram2_read       = 1'b0;
	assign ram2_writedata  = 64'd0;
	assign ram2_byteenable = 8'd0;
	assign ram2_write      = 1'b0;
	assign ram2_bcnt       = 8'd0;
`endif

wire clk_pal = clk_audio;


wire  [27:0] vbuf_address;
wire   [7:0] vbuf_burstcount;
wire         vbuf_waitrequest;
wire [127:0] vbuf_readdata;
wire         vbuf_readdatavalid;
wire         vbuf_read;
wire [127:0] vbuf_writedata;
wire  [15:0] vbuf_byteenable;
wire         vbuf_write;

`ifdef MISTER_DEBUG_NOHDMI
	// DE25: Ohne Scaler treibt niemand den vbuf-Port. Seit P3 hängt er
	// wirklich am DDR (sysmem_de25 -> F2SDRAM) — offene read/write-Leitungen
	// lösten dort Zugriffe aus. Daher fest auf "nichts tun".
	assign vbuf_address    = 28'd0;
	assign vbuf_burstcount = 8'd0;
	assign vbuf_read       = 1'b0;
	assign vbuf_write      = 1'b0;
	assign vbuf_writedata  = 128'd0;
	assign vbuf_byteenable = 16'd0;
`endif

wire  [23:0] hdmi_data;
wire         hdmi_vs, hdmi_hs, hdmi_de, hdmi_vbl, hdmi_brd;
wire         freeze;
wire         bob_deint;

`ifndef MISTER_DEBUG_NOHDMI
	wire clk_hdmi  = hdmi_clk_out;

	// DE25 (Quartus Pro): boolesche VHDL-Generics als 1'b0/1'b1 statt
	// "false"/"true" — Pro liest die Zeichenkette als Zahl (Fehler 13832).
	ascal 
	#(
		.RAMBASE(32'h20000000),
	`ifdef MISTER_SMALL_VBUF
		.RAMSIZE(32'h00200000),
	`else
		.RAMSIZE(32'h00800000),
	`endif
	`ifndef MISTER_FB
		.PALETTE2(1'b0),
	`else
		`ifndef MISTER_FB_PALETTE
			.PALETTE2(1'b0),
		`endif
	`endif
	`ifdef MISTER_DISABLE_ADAPTIVE
		.ADAPTIVE(1'b0),
	`endif
	`ifdef MISTER_DOWNSCALE_NN
		.DOWNSCALE_NN(1'b1),
	`endif
		.FRAC(8),
`ifdef MENU_CORE
		.N_BURST(2048),
`endif
		.N_DW(128),
		.N_AW(28)
	)
	ascal
	(
		.reset_na   (~reset_req),
		.run        (1),
		.freeze     (freeze),
		.bob_deint  (bob_deint),

		.i_clk    (clk_ihdmi),
		.i_ce     (ce_hpix),
		.i_r      (hr_out),
		.i_g      (hg_out),
		.i_b      (hb_out),
		.i_hs     (hhs_fix),
		.i_vs     (hvs_fix),
		.i_fl     (f1),
		.i_de     (hde_emu),
		.iauto    (1),
		.himin    (0),
		.himax    (0),
		.vimin    (0),
		.vimax    (0),

		.o_clk    (clk_hdmi),
		.o_ce     (scaler_out),
		.o_r      (hdmi_data[23:16]),
		.o_g      (hdmi_data[15:8]),
		.o_b      (hdmi_data[7:0]),
		.o_hs     (hdmi_hs),
		.o_vs     (hdmi_vs),
		.o_de     (hdmi_de),
		.o_vbl    (hdmi_vbl),
		.o_brd    (hdmi_brd),
		.o_lltune (lltune),
		.htotal   (WIDTH + HFP + HBP + HS[11:0]),
		.hsstart  (WIDTH + HFP),
		.hsend    (WIDTH + HFP + HS[11:0]),
		.hdisp    (WIDTH),
		.hmin     (hmin),
		.hmax     (hmax),
		.vtotal   (HEIGHT + VFP + VBP + VS[11:0]),
		.vsstart  (HEIGHT + VFP),
		.vsend    (HEIGHT + VFP + VS[11:0]),
		.vdisp    (HEIGHT),
		.vmin     (vmin),
		.vmax     (vmax),
		.vrr      (vrr_mode),
		.vrrmax   (HEIGHT + VBP + VS[11:0] + 12'd1),
		.swblack  (hdmi_blackout),

		.mode     ({~lowlat,LFB_EN ? LFB_FLT : |scaler_flt,2'b00}),
		.poly_clk (clk_sys),
		.poly_a   (coef_addr),
		.poly_dw  (coef_data),
		.poly_wr  (coef_wr),

		.pal1_clk (clk_pal),
		.pal1_dw  (pal_d),
		.pal1_a   (pal_a),
		.pal1_wr  (pal_wr),

	`ifdef MISTER_FB
		`ifdef MISTER_FB_PALETTE
			.pal2_clk (fb_pal_clk),
			.pal2_dw  (fb_pal_d),
			.pal2_dr  (fb_pal_q),
			.pal2_a   (fb_pal_a),
			.pal2_wr  (fb_pal_wr),
			.pal_n    (fb_en),
		`endif
	`endif

		.o_fb_ena         (FB_EN),
		.o_fb_hsize       (FB_WIDTH),
		.o_fb_vsize       (FB_HEIGHT),
		.o_fb_format      (FB_FMT),
		.o_fb_base        (FB_BASE),
		.o_fb_stride      (FB_STRIDE),

		.avl_clk          (clk_100m),
		.avl_waitrequest  (vbuf_waitrequest),
		.avl_readdata     (vbuf_readdata),
		.avl_readdatavalid(vbuf_readdatavalid),
		.avl_burstcount   (vbuf_burstcount),
		.avl_writedata    (vbuf_writedata),
		.avl_address      (vbuf_address),
		.avl_write        (vbuf_write),
		.avl_read         (vbuf_read),
		.avl_byteenable   (vbuf_byteenable)
	);
`endif

reg        LFB_EN     = 0;
reg        LFB_FLT    = 0;
reg  [5:0] LFB_FMT    = 0;
reg [11:0] LFB_WIDTH  = 0;
reg [11:0] LFB_HEIGHT = 0;
reg [11:0] LFB_HMIN   = 0;
reg [11:0] LFB_HMAX   = 0;
reg [11:0] LFB_VMIN   = 0;
reg [11:0] LFB_VMAX   = 0;
reg [31:0] LFB_BASE   = 0;
reg [13:0] LFB_STRIDE = 0;

reg        FB_EN     = 0;
reg  [5:0] FB_FMT    = 0;
reg [11:0] FB_WIDTH  = 0;
reg [11:0] FB_HEIGHT = 0;
reg [31:0] FB_BASE   = 0;
reg [13:0] FB_STRIDE = 0;

always @(posedge clk_sys) begin
	FB_EN <= LFB_EN | fb_en;
	if(LFB_EN) begin
		FB_FMT    <= LFB_FMT;
		FB_WIDTH  <= LFB_WIDTH;
		FB_HEIGHT <= LFB_HEIGHT;
		FB_BASE   <= LFB_BASE;
		FB_STRIDE <= LFB_STRIDE;
	end
	else begin
		FB_FMT    <= fb_fmt;
		FB_WIDTH  <= fb_width;
		FB_HEIGHT <= fb_height;
		FB_BASE   <= fb_base;
		FB_STRIDE <= fb_stride;
	end
end

`ifdef MISTER_FB
	reg fb_vbl;
	always @(posedge clk_vid) fb_vbl <= hdmi_vbl;
`endif

reg  ar_md_start;
wire ar_md_busy;
reg  [11:0] ar_md_mul1, ar_md_mul2, ar_md_div;
wire [11:0] ar_md_res;

sys_umuldiv #(12,12,12) ar_muldiv
(
	.clk(clk_vid),
	.start(ar_md_start),
	.busy(ar_md_busy),

	.mul1(ar_md_mul1),
	.mul2(ar_md_mul2),
	.div(ar_md_div),
	.result(ar_md_res)
);

reg [11:0] hmin;
reg [11:0] hmax;
reg [11:0] vmin;
reg [11:0] vmax;
reg [11:0] hdmi_height;
reg [11:0] hdmi_width;

reg [11:0] arx;
reg [11:0] ary;
reg        arxy;

always @(posedge clk_vid) begin
	reg [11:0] hmini,hmaxi,vmini,vmaxi;
	reg [11:0] wcalc,videow;
	reg [11:0] hcalc,videoh;
	reg  [2:0] state;

	hdmi_height <= (VSET && (VSET < HEIGHT)) ? VSET : HEIGHT;
	hdmi_width  <= (HSET && (HSET < WIDTH))  ? HSET << HDMI_PR : WIDTH << HDMI_PR;

	if(!ARY) begin
		if(ARX == 1) begin
			arx  <= arc1x[11:0];
			ary  <= arc1y[11:0];
			arxy <= arc1x[12] | arc1y[12];
		end
		else if(ARX == 2) begin
			arx  <= arc2x[11:0];
			ary  <= arc2y[11:0];
			arxy <= arc2x[12] | arc2y[12];
		end
		else begin
			arx  <= 0;
			ary  <= 0;
			arxy <= 0;
		end
	end
	else begin
		arx  <= ARX[11:0];
		ary  <= ARY[11:0];
		arxy <= ARX[12] | ARY[12];
	end
	
	ar_md_start <= 0;
	state <= state + 1'd1;
	case(state)
		0: if(LFB_EN) begin
				hmini <= LFB_HMIN;
				vmini <= LFB_VMIN;
				hmaxi <= LFB_HMAX;
				vmaxi <= LFB_VMAX;
				state <= 0;
			end
			else if(FREESCALE || !arx || !ary) begin
				wcalc <= hdmi_width;
				hcalc <= hdmi_height;
				state <= 6;
			end
			else if(arxy) begin
				wcalc <= arx;
				hcalc <= ary;
				state <= 6;
			end

		1: begin
				ar_md_mul1 <= hdmi_height;
				ar_md_mul2 <= arx;
				ar_md_div  <= ary;
				ar_md_start<= 1;
			end
		2: begin
				wcalc <= ar_md_res;
				if(ar_md_start | ar_md_busy) state <= 2;
			end

		3: begin
				ar_md_mul1 <= hdmi_width;
				ar_md_mul2 <= ary;
				ar_md_div  <= arx;
				ar_md_start<= 1;
			end
		4: begin
				hcalc <= ar_md_res;
				if(ar_md_start | ar_md_busy) state <= 4;
			end

		6: begin
				videow <= (wcalc > hdmi_width)  ? (hdmi_width >> HDMI_PR)  : (wcalc[11:0] >> HDMI_PR);
				videoh <= (hcalc > hdmi_height) ? hdmi_height : hcalc[11:0];
			end

		7: begin
				hmini <= ((WIDTH  - videow)>>1);
				hmaxi <= ((WIDTH  - videow)>>1) + videow - 1'd1;
				vmini <= ((HEIGHT - videoh)>>1);
				vmaxi <= ((HEIGHT - videoh)>>1) + videoh - 1'd1;
			end
	endcase
	
	hmin <= hmini;
	hmax <= hmaxi;
	vmin <= vmini;
	vmax <= vmaxi;
end

// DE25: pll_hdmi_adj (Low-Latency-Nachregelung der HDMI-PLL) entfällt: es
// verstellt den fraktionalen K-Wert, den die Agilex-5-IOPLL nicht hat.
// led_locked zeigt das Einrasten der HDMI-PLL.
wire hdmi_pll_locked;
`ifndef MISTER_DEBUG_NOHDMI
	wire [15:0] lltune;
	assign led_locked = hdmi_pll_locked;
`else
	assign led_locked = 0;
`endif

// DE25: pal_data, pal_d, pal_a, pal_wr oben deklariert (vor ddr_svc)
assign pal_d = {pal_data[55:32], pal_data[23:0]};
assign pal_a = ram2_bcnt[6:0];
`ifdef MISTER_DEBUG_NOHDMI
assign pal_data = 64'd0;   // DE25: ohne ddr_svc (siehe oben)
assign pal_wr   = 1'b0;
`endif

reg  [28:0] pal_addr;
reg         pal_req = 0;
always @(posedge clk_pal) begin
	reg old_vs1, old_vs2;

	pal_addr <= LFB_BASE[31:3] - 29'd512;

	old_vs1 <= hdmi_vs;
	old_vs2 <= old_vs1;
	
	if(~old_vs2 & old_vs1 & ~FB_FMT[2] & FB_FMT[1] & FB_FMT[0] & FB_EN) pal_req <= ~pal_req;
end


/////////////////////////  HDMI output  /////////////////////////////////

// DE25: Einschalt-Reset für pll_cfg_de25 und i2c_master_de25 (FPGA_CLK1_50)
reg [3:0] cfg_por_cnt = 4'd15;
wire      cfg_por_rst = |cfg_por_cnt;
always @(posedge FPGA_CLK1_50) if (cfg_por_rst) cfg_por_cnt <= cfg_por_cnt - 1'd1;

// DE25: Registerzugriffe von Linux in der Domäne FPGA_CLK1_50 (disk_m0 über
// avl_slow_cdc, siehe "HPS-System" unten): 0x1000 PLL-Debug, 0x2000 I2C,
// 0x3000 DDR-Sperre
wire [13:0] dm_b_address;
wire        dm_b_write, dm_b_read;
wire [31:0] dm_b_writedata;
wire        dm_b_sel_pll = (dm_b_address[13:12] == 2'd1);
wire        dm_b_sel_i2c = (dm_b_address[13:12] == 2'd2);
wire        dm_b_sel_halt = (dm_b_address[13:12] == 2'd3);

// DE25: DDR-Sperre vor dem Umladen (Main, de25/fpga_io.cpp). Wird das FPGA
// mitten in einem F2SDRAM-Zugriff neu geladen, hängt die SMMU und mit ihr
// Linux. Main setzt deshalb vorher halt und wartet auf idle (alle drei Ports
// angehalten und leer, sys/de25/f2s_halt_de25.v).
//   0x3000 W [0] halt
//          R [0] halt, [3:1] idle (ram1, ram2, vbuf), [31:16] 0x4844 ("HD")
wire [2:0] f2s_halt_idle_s;   // f2s_halt_q, f2s_halt_idle: bei sysmem oben
sync_2ff #(.WIDTH(3)) f2s_idle_sync(.clk(FPGA_CLK1_50), .d_async(f2s_halt_idle), .d_sync_q(f2s_halt_idle_s));
always @(posedge FPGA_CLK1_50) begin
	if (cfg_por_rst) f2s_halt_q <= 1'b0;
	else if (dm_b_write && dm_b_sel_halt && dm_b_address[5:2] == 4'd0) f2s_halt_q <= dm_b_writedata[0];
end
wire [31:0] halt_readdata = {16'h4844, 12'd0, f2s_halt_idle_s, f2s_halt_q};
wire [31:0] pll_dbg_readdata, i2c_readdata;
`ifndef MISTER_DEBUG_NOHDMI
	// DE25: ganzzahlige IOPLL (HVIO, Startwert 148,5 MHz = höchster Takt, so
	// prüft Quartus das Timing für den schlimmsten Fall; passt zu den
	// Startwerten 1920x1080 unten) statt
	// MiSTers fraktionaler pll_hdmi. Umgestellt wird sie über ihren Port
	// core_avl_* von pll_cfg_de25 (unten). Kein Reset durch den Core: das
	// HDMI-Bild (und das OSD darüber) soll beim Core-Reset bleiben.
	wire hdmi_clk_out;
	wire [8:0] pll_avl_address;
	wire       pll_avl_read, pll_avl_write;
	wire [7:0] pll_avl_writedata, pll_avl_readdata;
	// Referenz CLOCK1_50 (FPGA_CLK3_50): nur ein Takt von einem HVIO-Pin
	// macht daraus eine HVIO-IOPLL — nur die hat core_avl_*. CLOCK0_50
	// (FPGA_CLK1_50) liegt in einer HSIO-Bank und ergäbe eine IO96B-PLL.
	pll_hdmi_de25 pll_hdmi
	(
		.refclk(FPGA_CLK3_50),
		.rst(1'b0),
		.outclk_0(hdmi_clk_out),
		.locked(hdmi_pll_locked),
		.core_avl_clk(FPGA_CLK1_50),
		.core_avl_address(pll_avl_address),
		.core_avl_read(pll_avl_read),
		.core_avl_write(pll_avl_write),
		.core_avl_writedata(pll_avl_writedata),
		.core_avl_readdata(pll_avl_readdata)
	);
`endif

//1920x1080@60 PCLK=148.5MHz CEA
reg  [11:0] WIDTH   = 1920;
reg  [11:0] HFP     = 88;
reg  [12:0] HS      = 48;
reg  [11:0] HBP     = 148;
reg  [11:0] HEIGHT  = 1080;
reg  [11:0] VFP     = 4;
reg  [12:0] VS      = 5;
reg  [11:0] VBP     = 36;
reg         HDMI_PR = 0;

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest,adj_waitrequest;
wire        cfg_write;
wire  [5:0] cfg_address;
wire [31:0] cfg_data;
reg         adj_write;
reg   [5:0] adj_address;
reg  [31:0] adj_data;

`ifndef MISTER_DEBUG_NOHDMI
	// DE25: pll_cfg_de25 statt pll_cfg_hdmi; ohne pll_hdmi_adj schreibt die
	// Logik unten (unverändert) direkt hinein (adj_* = cfg_*). Main schickt
	// die PLL-Werte im Cyclone-V-Format, pll_cfg_de25 übersetzt sie.
	// Kein Reset durch den Core (reset_req), damit ein Core-Reset keinen
	// laufenden Umstellvorgang abbricht; nur ein Einschalt-Reset.
	assign cfg_waitrequest = adj_waitrequest;
	pll_cfg_de25 pll_cfg
	(
		.clk(FPGA_CLK1_50),
		.rst(cfg_por_rst),
		.mgmt_write(adj_write),
		.mgmt_address(adj_address),
		.mgmt_writedata(adj_data),
		.mgmt_waitrequest(adj_waitrequest),
		.dbg_address(dm_b_address[5:2]),
		.dbg_write(dm_b_write & dm_b_sel_pll),
		.dbg_writedata(dm_b_writedata),
		.dbg_read(dm_b_read & dm_b_sel_pll),
		.dbg_readdata(pll_dbg_readdata),
		.core_avl_address(pll_avl_address),
		.core_avl_read(pll_avl_read),
		.core_avl_write(pll_avl_write),
		.core_avl_writedata(pll_avl_writedata),
		.core_avl_readdata(pll_avl_readdata),
		.pll_locked(hdmi_pll_locked)
	);

	reg cfg_got = 0;
	always @(posedge clk_sys) begin
		reg vsd, vsd2;
		if(~cfg_ready || ~cfg_set) cfg_got <= cfg_set;
		else begin
			vsd  <= HDMI_TX_VS;
			vsd2 <= vsd;
			if(~vsd2 & vsd) cfg_got <= cfg_set;
		end
	end

	reg cfg_ready = 0;
	always @(posedge FPGA_CLK1_50) begin
		reg gotd, gotd2;     // DE25: ohne Startwert (Warnung 16754)
		reg custd, custd2;
		reg old_wait;

		gotd  <= cfg_got;
		gotd2 <= gotd;
		
		adj_write <= 0;
		
		custd <= cfg_custom_t;
		custd2 <= custd;
		if(custd2 != custd & ~gotd) begin
			adj_address <= cfg_custom_p1;
			adj_data <= cfg_custom_p2;
			adj_write <= 1;
		end

		if(~gotd2 & gotd) begin
			adj_address <= 2;
			adj_data <= 0;
			adj_write <= 1;
		end

		old_wait <= adj_waitrequest;
		if(old_wait & ~adj_waitrequest & gotd) cfg_ready <= 1;
	end
`else
	wire cfg_ready = 1;
`endif


// DE25: Der HDMI-Sender hängt an FPGA-Pins, nicht am I2C des HPS. Main
// stellt ihn wie bei MiSTer selbst ein, über i2c_master_de25 (Linux
// 0x2001_6000, linux/main/de25/smbus.cpp). Bis Main den Bus übernimmt
// (own = 1), konfiguriert ihn hdmi_config aus dem C64-Projekt (100 kHz bei
// 50 MHz) — so gibt es auch ohne Main ein Bild.
wire i2c_own, i2c_scl_en, i2c_sda_en;
wire hdmi_scl_en, hdmi_sda_en;
wire hdmi_cfg_rst;
wire hdmi_cfg_ready, hdmi_cfg_nack;
assign HDMI_I2C_SCL = (i2c_own ? i2c_scl_en : hdmi_scl_en) ? 1'b0 : 1'bZ;
assign HDMI_I2C_SDA = (i2c_own ? i2c_sda_en : hdmi_sda_en) ? 1'b0 : 1'bZ;

i2c_master_de25 #(.QUARTER(16'd125)) hdmi_i2c
(
	.clk(FPGA_CLK1_50),
	.rst(cfg_por_rst),
	.address(dm_b_address[5:2]),
	.write(dm_b_write & dm_b_sel_i2c),
	.writedata(dm_b_writedata),
	.read(dm_b_read & dm_b_sel_i2c),
	.readdata(i2c_readdata),
	.own(i2c_own),
	.scl_oe(i2c_scl_en),
	.sda_oe(i2c_sda_en),
	.sda_in(HDMI_I2C_SDA),
	.scl_in(HDMI_I2C_SCL),
	.diag_in({hdmi_cfg_nack, hdmi_cfg_ready, hdmi_cfg_rst})
);

sync_2ff hdmi_cfg_rst_sync(.clk(FPGA_CLK1_50), .d_async(reset), .d_sync_q(hdmi_cfg_rst));

hdmi_config #(.CLKS_PER_QUARTER(125), .STARTUP_CLKS(10_000_000)) hdmi_cfg
(
	.clk(FPGA_CLK1_50),
	.rst(hdmi_cfg_rst | i2c_own),   // ruht, solange Main den Bus hat
	.int_n(HDMI_TX_INT),
	.scl_oe_q(hdmi_scl_en),
	.sda_oe_q(hdmi_sda_en),
	.sda_in(HDMI_I2C_SDA),
	.ready_q(hdmi_cfg_ready),
	.nack_q(hdmi_cfg_nack)
);

`ifndef MISTER_DEBUG_NOHDMI
	`ifdef MISTER_FB
	reg dis_output;
	always @(posedge clk_hdmi) begin
		reg dis;
		dis <= fb_force_blank & ~LFB_EN;
		dis_output <= dis;
	end
	`else
	wire dis_output = 0;
	`endif

	wire [23:0] hdmi_data_mask;
	wire        hdmi_de_mask, hdmi_vs_mask, hdmi_hs_mask;

	reg [15:0] shadowmask_data;
	reg        shadowmask_wr = 0;

	shadowmask HDMI_shadowmask
	(
		.clk(clk_hdmi),
		.clk_sys(clk_sys),

		.cmd_wr(shadowmask_wr),
		.cmd_in(shadowmask_data),

		.din(dis_output ? 24'd0 : hdmi_data),
		.hs_in(hdmi_hs),
		.vs_in(hdmi_vs),
		.de_in(hdmi_de),
		.brd_in(hdmi_brd),
		.enable(~LFB_EN),

		.dout(hdmi_data_mask),
		.hs_out(hdmi_hs_mask),
		.vs_out(hdmi_vs_mask),
		.de_out(hdmi_de_mask)
	);

	wire [23:0] hdmi_data_osd;
	wire        hdmi_de_osd, hdmi_vs_osd, hdmi_hs_osd;

	osd hdmi_osd
	(
		.clk_sys(clk_sys),

		.io_osd(io_osd_hdmi),
		.io_strobe(io_strobe),
		.io_din(io_din),

		.clk_video(clk_hdmi),
		.din(hdmi_data_mask),
		.hs_in(hdmi_hs_mask),
		.vs_in(hdmi_vs_mask),
		.de_in(hdmi_de_mask),

		.dout(hdmi_data_osd),
		.hs_out(hdmi_hs_osd),
		.vs_out(hdmi_vs_osd),
		.de_out(hdmi_de_osd)
	);

	wire hdmi_cs_osd;
	csync csync_hdmi(clk_hdmi, hdmi_hs_osd, hdmi_vs_osd, hdmi_cs_osd);
`endif

reg [23:0] dv_data;
reg        dv_hs, dv_vs, dv_de;
wire [23:0] dv_data_osd;
wire dv_hs_osd, dv_vs_osd, dv_cs_osd;

always @(posedge clk_vid) begin
	reg [23:0] dv_d1, dv_d2;
	reg        dv_de1, dv_de2, dv_hs1, dv_hs2, dv_vs1, dv_vs2;
	reg [12:0] vsz, vcnt, vcnt_l, vcnt_ll;
	reg        old_hs, old_vs;
	reg        vde;
	reg  [3:0] hss;

	if(ce_pix) begin
		hss <= (hss << 1) | dv_hs_osd;

		old_hs <= dv_hs_osd;
		if(~old_hs && dv_hs_osd) begin
			old_vs <= dv_vs_osd;
			if(~&vcnt) vcnt <= vcnt + 1'd1;
			if(~old_vs & dv_vs_osd) begin
				if (vcnt != vcnt_ll || vcnt < vcnt_l) vsz <= vcnt;
				vcnt_l <= vcnt;
				vcnt_ll <= vcnt_l;
			end
			if(old_vs & ~dv_vs_osd) vcnt <= 0;
			
			if(vcnt == 1) vde <= 1;
			if(vcnt == vsz - 3) vde <= 0;
		end

		// DE25: MiSTer bildet DE hier aus HS/VS nach (für VGA-Adapter, denen
		// DE egal ist). Der HDMI-Sender richtet sich aber nach DE — daher
		// das DE des Cores (nach OSD) durchreichen.
		dv_de1 <= vga_de_osd;
	end

	dv_d1  <= dv_data_osd;
	dv_hs1 <= csync_en ? dv_cs_osd : dv_hs_osd;
	dv_vs1 <= dv_vs_osd;

	dv_d2  <= dv_d1;
	dv_de2 <= dv_de1;
	dv_hs2 <= dv_hs1;
	dv_vs2 <= dv_vs1;

	dv_data<= dv_d2;
	dv_de  <= dv_de2;
	dv_hs  <= dv_hs2;
	dv_vs  <= dv_vs2;
end

`ifndef MISTER_DISABLE_YC
	assign {dv_data_osd, dv_hs_osd, dv_vs_osd, dv_cs_osd } = ~yc_en ? {vga_data_osd, vga_hs_osd, vga_vs_osd, vga_cs_osd } : {yc_o, yc_hs, yc_vs, yc_cs };
`else
	assign {dv_data_osd, dv_hs_osd, dv_vs_osd, dv_cs_osd } = {vga_data_osd, vga_hs_osd, vga_vs_osd, vga_cs_osd };
`endif

wire hdmi_tx_clk;
// DE25: Statt altddio_out geht der Takt direkt an den Pin; die
// Ausgangsregister unten schalten dafür mit der fallenden Flanke, der Sender
// übernimmt eine halbe Periode später mit der steigenden.
// Mit Scaler: HDMI-Takt der festen PLL. MiSTers Umschalter auf den Core-Takt
// für direct_video=1 fehlt noch — direct_video wird nicht unterstützt.
`ifndef MISTER_DEBUG_NOHDMI
assign hdmi_tx_clk = clk_hdmi;
`else
assign hdmi_tx_clk = clk_vid;
`endif
assign HDMI_TX_CLK = hdmi_tx_clk;

reg hdmi_out_hs;
reg hdmi_out_vs;
reg hdmi_out_de;
reg [23:0] hdmi_out_d;

// DE25: fallende Flanke, siehe oben
always @(negedge hdmi_tx_clk) begin
	reg [23:0] hdmi_dv_data;
	reg        hdmi_dv_hs, hdmi_dv_vs, hdmi_dv_de;

	reg hs,vs,de;
	reg [23:0] d;
	
	hdmi_dv_data <= dv_data;
	hdmi_dv_hs   <= dv_hs;
	hdmi_dv_vs   <= dv_vs;
	hdmi_dv_de   <= dv_de;
	
`ifndef MISTER_DEBUG_NOHDMI
	hs <= (~vga_fb & direct_video) ? hdmi_dv_hs   : (direct_video & csync_en) ? hdmi_cs_osd : hdmi_hs_osd;
	vs <= (~vga_fb & direct_video) ? hdmi_dv_vs   : hdmi_vs_osd;
	de <= (~vga_fb & direct_video) ? hdmi_dv_de   : hdmi_de_osd;
	d  <= (~vga_fb & direct_video) ? hdmi_dv_data : hdmi_data_osd;
`else
	hs <= hdmi_dv_hs;
	vs <= hdmi_dv_vs;
	de <= hdmi_dv_de;
	d  <= hdmi_dv_data;
`endif

	hdmi_out_hs <= hs;
	hdmi_out_vs <= vs;
	hdmi_out_de <= de;
	hdmi_out_d  <= d;
end

assign HDMI_TX_HS = hdmi_out_hs;
assign HDMI_TX_VS = hdmi_out_vs;
assign HDMI_TX_DE = hdmi_out_de;
assign HDMI_TX_D  = hdmi_out_d;

/////////////////////////  VGA output  //////////////////////////////////

// DE25: kein analoger VGA-Ausgang (Taktausgang entfällt)

wire [23:0] vga_data_sl;
wire        vga_de_sl, vga_ce_sl, vga_vs_sl, vga_hs_sl;
scanlines #(0) VGA_scanlines
(
	.clk(clk_vid),

	.scanlines(scanlines),
	.din(de_emu ? {r_out, g_out, b_out} : 24'd0),
	.hs_in(hs_fix),
	.vs_in(vs_fix),
	.de_in(de_emu),
	.ce_in(ce_pix),

	.dout(vga_data_sl),
	.hs_out(vga_hs_sl),
	.vs_out(vga_vs_sl),
	.de_out(vga_de_sl),
	.ce_out(vga_ce_sl)
);

wire [23:0] vga_data_osd;
wire        vga_vs_osd, vga_hs_osd, vga_de_osd;
osd vga_osd
(
	.clk_sys(clk_sys),

	.io_osd(io_osd_vga),
	.io_strobe(io_strobe),
	.io_din(io_din),
	.osd_status(osd_status),

	.clk_video(clk_vid),
	.din(vga_data_sl),
	.hs_in(vga_hs_sl),
	.vs_in(vga_vs_sl),
	.de_in(vga_de_sl),

	.dout(vga_data_osd),
	.hs_out(vga_hs_osd),
	.vs_out(vga_vs_osd),
	.de_out(vga_de_osd)
);

wire vga_cs_osd;
csync csync_vga(clk_vid, vga_hs_osd, vga_vs_osd, vga_cs_osd);

`ifndef MISTER_DISABLE_YC
	reg         pal_en;
	reg         yc_en;
	reg         cvbs;
	reg  [16:0] ColorBurst_Range;
	wire [23:0] yc_o;
	wire        yc_hs, yc_vs, yc_cs, yc_de;

	yc_out yc_out
	(
		.clk(clk_vid),
		.PAL_EN(pal_en),
		.CVBS(cvbs),
		.PHASE_INC(PhaseInc),
		.COLORBURST_RANGE(ColorBurst_Range),
		.hsync(vga_hs_osd),
		.vsync(vga_vs_osd),
		.csync(vga_cs_osd),
		.de(vga_de_osd),
		.dout(yc_o),
		.din(vga_data_osd),
		.hsync_o(yc_hs),
		.vsync_o(yc_vs),
		.csync_o(yc_cs),
		.de_o(yc_de)
	);
`endif

reg  [39:0] PhaseInc;

// DE25: kein analoger VGA-Ausgang (Hilfsträger, vga_out entfallen)
reg  subcarrier;
wire VGA_DISABLE;

reg video_sync = 0;
always @(posedge clk_vid) begin
	reg [11:0] line_cnt;     // DE25: ohne Startwert (Warnung 16754)
	reg [11:0] sync_line;
	reg  [1:0] hs_cnt;
	reg        old_hs;

	old_hs <= hs_fix;
	if(~old_hs & hs_fix) begin

		video_sync <= (sync_line == line_cnt);

		line_cnt <= line_cnt + 1'd1;
		if(~hs_cnt[1]) begin	
			hs_cnt <= hs_cnt + 1'd1;
			if(hs_cnt[0]) begin
				sync_line <= (line_cnt - vs_line);
				line_cnt <= 0;
			end
		end
	end

	if(de_emu) hs_cnt <= 0;
end

/////////////////////////  Audio output  ////////////////////////////////

// DE25: keine analogen Audio-/SPDIF-Ausgänge
wire analog_l, analog_r;

assign HDMI_MCLK = clk_audio;
wire clk_audio;

// DE25: Referenz getauscht mit pll_hdmi (die braucht den HVIO-Takt CLOCK1_50)
pll_audio pll_audio
(
	.refclk(FPGA_CLK1_50),
	.rst(0),
	.outclk_0(clk_audio)
);

wire spdif;
audio_out audio_out
(
	.reset(reset | areset),
	.clk(clk_audio),

	.att(vol_att),
	.boost(vol_boost),
	.mix(audio_mix),
	.sample_rate(audio_96k),

	.flt_rate(aflt_rate),
	.cx(acx),
	.cx0(acx0),
	.cx1(acx1),
	.cx2(acx2),
	.cy0(acy0),
	.cy1(acy1),
	.cy2(acy2),

	.is_signed(audio_s),
	.core_l(audio_l),
	.core_r(audio_r),

`ifndef MISTER_DISABLE_ALSA
	.alsa_l(alsa_l),
	.alsa_r(alsa_r),
`endif

	.i2s_bclk(HDMI_SCLK),
	.i2s_lrclk(HDMI_LRCLK),
	.i2s_data(HDMI_I2S),
`ifndef MISTER_DUAL_SDRAM
	.dac_l(analog_l),
	.dac_r(analog_r),
`endif
	.spdif(spdif)
);


`ifndef MISTER_DISABLE_ALSA
	wire aspi_sck,aspi_mosi,aspi_ss,aspi_miso;
	cyclonev_hps_interface_peripheral_spi_master spi
	(
		.sclk_out(aspi_sck),
		.txd(aspi_mosi), // mosi
		.rxd(aspi_miso), // miso

		.ss_0_n(aspi_ss),
		.ss_in_n(1)
	);

	wire [28:0] alsa_address;
	wire [63:0] alsa_readdata;
	wire        alsa_ready;
	wire        alsa_req;
	wire        alsa_late;

	wire [15:0] alsa_l, alsa_r;

	alsa alsa
	(
		.reset(reset),
		.clk(clk_audio),

		.ram_address(alsa_address),
		.ram_data(alsa_readdata),
		.ram_req(alsa_req),
		.ram_ready(alsa_ready),

		.spi_ss(aspi_ss),
		.spi_sck(aspi_sck),
		.spi_mosi(aspi_mosi),
		.spi_miso(aspi_miso),

		.pcm_l(alsa_l),
		.pcm_r(alsa_r)
	);
`endif

////////////////  User I/O (USB 3.0 connector) /////////////////////////

// DE25: kein User-Port (USB-3.0-Buchse des DE10-Nano)
assign user_in = 7'h7F;


///////////////////  User module connection ////////////////////////////

wire        clk_sys;
wire [15:0] audio_l, audio_r;
wire        audio_s;
wire  [1:0] audio_mix;
wire  [1:0] scanlines;
wire  [7:0] r_out, g_out, b_out, hr_out, hg_out, hb_out;
wire        vs_fix, hs_fix, de_emu, vs_emu, hs_emu, f1;
wire        hvs_fix, hhs_fix, hde_emu;
wire        clk_vid, ce_pix, clk_ihdmi, ce_hpix;
wire        vga_force_scaler;

wire        ram_clk;
wire [28:0] ram_address;
wire [7:0]  ram_burstcount;
wire        ram_waitrequest;
wire [63:0] ram_readdata;
wire        ram_readdatavalid;
wire        ram_read;
wire [63:0] ram_writedata;
wire [7:0]  ram_byteenable;
wire        ram_write;

wire        led_user;
wire  [1:0] led_power;
wire  [1:0] led_disk;
wire  [1:0] btn;

sync_fix sync_v(clk_vid, vs_emu, vs_fix);
sync_fix sync_h(clk_vid, hs_emu, hs_fix);

wire  [6:0] user_out, user_in;

assign clk_ihdmi= clk_vid;
assign ce_hpix  = vga_ce_sl;
assign hr_out   = vga_data_sl[23:16];
assign hg_out   = vga_data_sl[15:8];
assign hb_out   = vga_data_sl[7:0];
assign hhs_fix  = vga_hs_sl;
assign hvs_fix  = vga_vs_sl;
assign hde_emu  = vga_de_sl;

wire uart_dtr = 1'b1;   // DE25: HPS-UART nicht angeschlossen (Ruhepegel)
wire uart_dsr;
wire uart_cts;
wire uart_rts = 1'b1;
wire uart_rxd;
wire uart_txd = 1'b1;

wire osd_status;

wire        fb_en;
wire  [4:0] fb_fmt;
wire [11:0] fb_width;
wire [11:0] fb_height;
wire [31:0] fb_base;
wire [13:0] fb_stride;


`ifdef MISTER_FB
	`ifdef MISTER_FB_PALETTE
		wire        fb_pal_clk;
		wire  [7:0] fb_pal_a;
		wire [23:0] fb_pal_d;
		wire [23:0] fb_pal_q;
		wire        fb_pal_wr;
		// DE25: Schattenkopie der Palette (Schreiben im Takt des Cores, Lesen
		// für UIO 0x4E im Takt clk_sys) — Mains Screenshot im Framebuffer-Modus
		reg [23:0] fbpal_shadow [0:255];
		always @(posedge fb_pal_clk) if (fb_pal_wr) fbpal_shadow[fb_pal_a] <= fb_pal_d;
		reg [15:0] fbpal_wcnt_c;
		always @(posedge fb_pal_clk) if (fb_pal_wr) fbpal_wcnt_c <= fbpal_wcnt_c + 1'd1;
		always @(posedge clk_sys) fbpal_wcnt <= fbpal_wcnt_c;   // nur Anzeige, Querung egal
		always @(posedge clk_sys) fbpal_q <= fbpal_shadow[fbpal_ra];
	`else
		// DE25: ohne Core-Palette liefert 0x4E nur Nullen
		always @(posedge clk_sys) {fbpal_q, fbpal_wcnt} <= 0;
	`endif
	wire   fb_force_blank;
`else
	// DE25: ohne Framebuffer liefert 0x4E nur Nullen
	always @(posedge clk_sys) {fbpal_q, fbpal_wcnt} <= 0;
	assign fb_en = 0;
	assign fb_fmt = 0;
	assign fb_width = 0;
	assign fb_height = 0;
	assign fb_base = 0;
	assign fb_stride = 0;
`endif

wire [3:0] adc_bus;

emu emu
(
	.CLK_50M(FPGA_CLK2_50),
	.RESET(reset),
	.HPS_BUS({f1, HDMI_TX_VS, 
				 clk_100m, clk_ihdmi,
				 ce_hpix, hde_emu, hhs_fix, hvs_fix, 
				 io_wait, clk_sys, io_fpga, io_uio, io_strobe, io_wide, io_din, io_dout}),

	.VGA_R(r_out),
	.VGA_G(g_out),
	.VGA_B(b_out),
	.VGA_HS(hs_emu),
	.VGA_VS(vs_emu),
	.VGA_DE(de_emu),
	.VGA_F1(f1),
	.VGA_SCALER(vga_force_scaler),

`ifndef MISTER_DUAL_SDRAM
	.VGA_DISABLE(VGA_DISABLE),
`endif

	.HDMI_WIDTH(direct_video ? 12'd0 : hdmi_width),
	.HDMI_HEIGHT(direct_video ? 12'd0 : hdmi_height),
	.HDMI_FREEZE(freeze),
	.HDMI_BLACKOUT(hdmi_blackout),
	.HDMI_BOB_DEINT(bob_deint),

	.LFB_FMT(LFB_FMT),
	.LFB_BASE(LFB_BASE),
	.LFB_WIDTH(LFB_WIDTH),
	.LFB_HEIGHT(LFB_HEIGHT),
	.LFB_STRIDE(LFB_STRIDE),

	.CLK_VIDEO(clk_vid),
	.CE_PIXEL(ce_pix),
	.VGA_SL(scanlines),
	.VIDEO_ARX(ARX),
	.VIDEO_ARY(ARY),

`ifdef MISTER_FB
	.FB_EN(fb_en),
	.FB_FORMAT(fb_fmt),
	.FB_WIDTH(fb_width),
	.FB_HEIGHT(fb_height),
	.FB_BASE(fb_base),
	.FB_STRIDE(fb_stride),
	.FB_VBL(fb_vbl),
	.FB_LL(lowlat),
	.FB_FORCE_BLANK(fb_force_blank),

`ifdef MISTER_FB_PALETTE
	.FB_PAL_CLK (fb_pal_clk),
	.FB_PAL_ADDR(fb_pal_a),
	.FB_PAL_DOUT(fb_pal_d),
	.FB_PAL_DIN (fb_pal_q),
	.FB_PAL_WR  (fb_pal_wr),
`endif

`endif

	.LED_USER(led_user),
	.LED_POWER(led_power),
	.LED_DISK(led_disk),

	.CLK_AUDIO(clk_audio),
	.AUDIO_L(audio_l),
	.AUDIO_R(audio_r),
	.AUDIO_S(audio_s),
	.AUDIO_MIX(audio_mix),

	.ADC_BUS(adc_bus),   // DE25: kein ADC-Anschluss wie beim DE10-Nano

	.DDRAM_CLK(ram_clk),
	.DDRAM_ADDR(ram_address),
	.DDRAM_BURSTCNT(ram_burstcount),
	.DDRAM_BUSY(ram_waitrequest),
	.DDRAM_DOUT(ram_readdata),
	.DDRAM_DOUT_READY(ram_readdatavalid),
	.DDRAM_RD(ram_read),
	.DDRAM_DIN(ram_writedata),
	.DDRAM_BE(ram_byteenable),
	.DDRAM_WE(ram_write),

	.SDRAM_DQ(SDRAM_DQ),
	.SDRAM_A(SDRAM_A),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nWE(SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CLK(SDRAM_CLK),
	.SDRAM_CKE(SDRAM_CKE),

`ifdef MISTER_DUAL_SDRAM
	.SDRAM2_DQ(SDRAM2_DQ),
	.SDRAM2_A(SDRAM2_A),
	.SDRAM2_BA(SDRAM2_BA),
	.SDRAM2_nCS(SDRAM2_nCS),
	.SDRAM2_nWE(SDRAM2_nWE),
	.SDRAM2_nRAS(SDRAM2_nRAS),
	.SDRAM2_nCAS(SDRAM2_nCAS),
	.SDRAM2_CLK(SDRAM2_CLK),
	.SDRAM2_EN(io_dig),
`endif

	.BUTTONS(btn),
	.OSD_STATUS(osd_status),

	.SD_SCK(SD_CLK),
	.SD_MOSI(SD_MOSI),
	.SD_MISO(SD_MISO),
	.SD_CS(SD_CS),
	.SD_CD(SD_CD),

	.UART_CTS(uart_rts),
	.UART_RTS(uart_cts),
	.UART_RXD(uart_txd),
	.UART_TXD(uart_rxd),
	.UART_DTR(uart_dsr),
	.UART_DSR(uart_dtr),

	.USER_OUT(user_out),
	.USER_IN(user_in)
);


/////////////////////////  HPS-System (DE25)  ////////////////////////////
// DE25: Terasics GHRD (qsys_top) mit den Brücken c64_m0 (hier: gp-Register)
// und disk_m0 (noch frei), wie im P0-Versuch.

wire clk_100;
wire ninit_done;

pll hps_pll
(
	.refclk(CLOCK2_50),
	.locked(),
	.rst(ninit_done),
	.outclk_0(clk_100)
);

wire rst_av;
sync_2ff rst_av_sync(.clk(clk_100), .d_async(ninit_done), .d_sync_q(rst_av));

wire  [3:0] gp_m0_address;
wire        gp_m0_write;
wire [31:0] gp_m0_writedata;
wire  [3:0] gp_m0_byteenable;
wire        gp_m0_read;
wire [31:0] gp_m0_readdata;
wire        gp_m0_readdatavalid;
wire        gp_m0_waitrequest;

// DE25: disk_m0 (Linux 0x2001_4000-0x2001_7FFF), aufgeteilt nach Adresse:
//   0x0000 video_debug: Messpunkte der Videokette (nur lesen, clk_100;
//          sys/de25/video_debug.v, Auswertung p3/linux/video_debug.py)
//   0x1000 pll_cfg_de25: Debug-Register der HDMI-PLL-Umstellung
//   0x2000 i2c_master_de25: I2C zum HDMI-Sender (für Main)
//   0x3000 DDR-Sperre vor dem Umladen (für Main)
// Die drei letzten liegen in FPGA_CLK1_50; avl_slow_cdc trägt die
// Zugriffe hinüber.
wire [13:0] disk_m0_address;
wire        disk_m0_write;
wire [31:0] disk_m0_writedata;
wire        disk_m0_read;
wire        disk_m0_readdatavalid;
wire [31:0] disk_m0_readdata;
wire        disk_m0_waitrequest;

wire        dm_sel_vd = (disk_m0_address[13:12] == 2'd0);
wire [31:0] vd_readdata, cdc_readdata;
wire        vd_readdatavalid, cdc_readdatavalid;
assign disk_m0_readdatavalid = vd_readdatavalid | cdc_readdatavalid;
assign disk_m0_readdata      = vd_readdatavalid ? vd_readdata : cdc_readdata;


avl_slow_cdc #(.AW(14)) dm_cdc
(
	.clk_a(clk_100),
	.rst_a(rst_av),
	.a_address(disk_m0_address),
	.a_write(disk_m0_write & ~dm_sel_vd),
	.a_writedata(disk_m0_writedata),
	.a_read(disk_m0_read & ~dm_sel_vd),
	.a_waitrequest(disk_m0_waitrequest),
	.a_readdata(cdc_readdata),
	.a_readdatavalid(cdc_readdatavalid),

	.clk_b(FPGA_CLK1_50),
	.b_address(dm_b_address),
	.b_write(dm_b_write),
	.b_writedata(dm_b_writedata),
	.b_read(dm_b_read),
	.b_readdata(dm_b_sel_pll ? pll_dbg_readdata : dm_b_sel_i2c ? i2c_readdata : halt_readdata)
);

`ifndef MISTER_DEBUG_NOHDMI
wire dbg_clk_hdmi = clk_hdmi;
wire dbg_out_vs   = hdmi_vs;
wire dbg_out_de   = hdmi_de;
`else
wire dbg_clk_hdmi = clk_vid;
wire dbg_out_vs   = 1'b0;
wire dbg_out_de   = 1'b0;
`endif

video_debug video_debug
(
	.clk_av(clk_100),
	.avs_address(disk_m0_address),
	.avs_read(disk_m0_read & dm_sel_vd & ~rst_av),
	.avs_readdata(vd_readdata),
	.avs_readdatavalid(vd_readdatavalid),

	.clk_vid(clk_vid),
	.core_vs(vs_fix),
	.core_de(de_emu),
	.in_ce(ce_hpix),
	.in_de(hde_emu),

	.clk_hdmi(dbg_clk_hdmi),
	.out_vs(dbg_out_vs),
	.out_de(dbg_out_de),

	.clk_vbuf(clk_100m),
	.vbuf_write(vbuf_write),
	.vbuf_read(vbuf_read),
	.vbuf_waitrequest(vbuf_waitrequest),
	.vbuf_readdatavalid(vbuf_readdatavalid),

	// Statusbits: 0 hdmi_pll_locked, 1 reset_req, 2 reset, 3 cfg_ready,
	// 4 cfg_done, 5 cfg_set, 6 direct_video, 7 vga_fb, 8 FB_EN, 9 LFB_EN,
	// 10 lowlat, 11 scaler_out (ascal o_ce), 12 HDMI_TX_VS, 13 HDMI_TX_DE,
	// 14 io_wait (ioctl_wait des Cores), 15 vs_wait, 16 io_ack, 17 io_uio
	// (Handshake zu Main: hängt io_ack, steht jeder Befehl von Main)
	.status({14'd0, io_uio, io_ack, vs_wait, io_wait, HDMI_TX_DE, HDMI_TX_VS, scaler_out, lowlat, LFB_EN, FB_EN,
	         vga_fb, direct_video, cfg_set, cfg_done, cfg_ready, reset, reset_req,
	         hdmi_pll_locked}),
	.info0({HFP[3:0], HEIGHT, HBP[3:0], WIDTH}),
	.info1({dbg_cmd20, dbg_strobes, dbg_cmd, dbg_cnt})
);

wire [2:0] hps_led;

qsys_top hps
(
	.disk_m0_waitrequest                   (disk_m0_waitrequest),
	.disk_m0_readdata                      (disk_m0_readdata),
	.disk_m0_readdatavalid                 (disk_m0_readdatavalid),
	.disk_m0_burstcount                    (),
	.disk_m0_writedata                     (disk_m0_writedata),
	.disk_m0_address                       (disk_m0_address),
	.disk_m0_write                         (disk_m0_write),
	.disk_m0_read                          (disk_m0_read),
	.disk_m0_byteenable                    (),
	.disk_m0_debugaccess                   (),
	.c64_m0_waitrequest                    (gp_m0_waitrequest),
	.c64_m0_readdata                       (gp_m0_readdata),
	.c64_m0_readdatavalid                  (gp_m0_readdatavalid),
	.c64_m0_burstcount                     (),
	.c64_m0_writedata                      (gp_m0_writedata),
	.c64_m0_address                        (gp_m0_address),
	.c64_m0_write                          (gp_m0_write),
	.c64_m0_read                           (gp_m0_read),
	.c64_m0_byteenable                     (gp_m0_byteenable),
	.c64_m0_debugaccess                    (),

	// DE25: DDR-Ports für sysmem (P3, sys/de25/hps_f2sdram_ports.tcl)
	.f2s_ram1_waitrequest                        (f2s_ram1_waitrequest),
	.f2s_ram1_readdata                           (f2s_ram1_readdata),
	.f2s_ram1_readdatavalid                      (f2s_ram1_readdatavalid),
	.f2s_ram1_burstcount                         (f2s_ram1_burstcount),
	.f2s_ram1_writedata                          (f2s_ram1_writedata),
	.f2s_ram1_address                            (f2s_ram1_address),
	.f2s_ram1_write                              (f2s_ram1_write),
	.f2s_ram1_read                               (f2s_ram1_read),
	.f2s_ram1_byteenable                         (f2s_ram1_byteenable),
	.f2s_ram1_debugaccess                        (1'b0),
	.f2s_ram1_clk_clk                            (f2s_ram1_clk),
	.f2s_ram2_waitrequest                        (f2s_ram2_waitrequest),
	.f2s_ram2_readdata                           (f2s_ram2_readdata),
	.f2s_ram2_readdatavalid                      (f2s_ram2_readdatavalid),
	.f2s_ram2_burstcount                         (f2s_ram2_burstcount),
	.f2s_ram2_writedata                          (f2s_ram2_writedata),
	.f2s_ram2_address                            (f2s_ram2_address),
	.f2s_ram2_write                              (f2s_ram2_write),
	.f2s_ram2_read                               (f2s_ram2_read),
	.f2s_ram2_byteenable                         (f2s_ram2_byteenable),
	.f2s_ram2_debugaccess                        (1'b0),
	.f2s_ram2_clk_clk                            (f2s_ram2_clk),
	.f2s_vbuf_waitrequest                        (f2s_vbuf_waitrequest),
	.f2s_vbuf_readdata                           (f2s_vbuf_readdata),
	.f2s_vbuf_readdatavalid                      (f2s_vbuf_readdatavalid),
	.f2s_vbuf_burstcount                         (f2s_vbuf_burstcount),
	.f2s_vbuf_writedata                          (f2s_vbuf_writedata),
	.f2s_vbuf_address                            (f2s_vbuf_address),
	.f2s_vbuf_write                              (f2s_vbuf_write),
	.f2s_vbuf_read                               (f2s_vbuf_read),
	.f2s_vbuf_byteenable                         (f2s_vbuf_byteenable),
	.f2s_vbuf_debugaccess                        (1'b0),
	.f2s_vbuf_clk_clk                            (f2s_vbuf_clk),

	.clk_100_clk                           (clk_100),
	.reset_reset_n                         (~ninit_done),
	.ninit_done_ninit_done                 (ninit_done),
	.led_pio_external_connection_in_port   (hps_led),
	.led_pio_external_connection_out_port  (hps_led),
	.dipsw_pio_external_connection_export  (4'b0000),
	.button_pio_external_connection_export (4'b1111),

	.hps_io_hps_osc_clk                    (HPS_CLK_25),
	.emif_hps_emif_mem_0_mem_cs            (LPDDR4A_CS_n),
	.emif_hps_emif_mem_0_mem_ca            (LPDDR4A_CA),
	.emif_hps_emif_mem_0_mem_cke           (LPDDR4A_CKE),
	.emif_hps_emif_mem_0_mem_dq            (LPDDR4A_DQ),
	.emif_hps_emif_mem_0_mem_dqs_t         (LPDDR4A_DQS),
	.emif_hps_emif_mem_0_mem_dqs_c         (LPDDR4A_DQS_n),
	.emif_hps_emif_mem_0_mem_dmi           (LPDDR4A_DM),
	.emif_hps_emif_mem_ck_0_mem_ck_t       (LPDDR4A_CK),
	.emif_hps_emif_mem_ck_0_mem_ck_c       (LPDDR4A_CK_n),
	.emif_hps_emif_mem_reset_n_mem_reset_n (LPDDR4A_RESET_n),
	.emif_hps_emif_oct_0_oct_rzqin         (LPDDR4A_RZQ),
	.emif_hps_emif_ref_clk_0_clk           (LPDDR4A_REFCLK_p),
	.hps_io_emac0_tx_clk                   (HPS_ENET_TX_CLK),
	.hps_io_emac0_rx_clk                   (HPS_ENET_RX_CLK),
	.hps_io_emac0_tx_ctl                   (HPS_ENET_TX_CTL),
	.hps_io_emac0_rx_ctl                   (HPS_ENET_RX_CTL),
	.hps_io_emac0_txd0                     (HPS_ENET_TX_DATA[0]),
	.hps_io_emac0_txd1                     (HPS_ENET_TX_DATA[1]),
	.hps_io_emac0_txd2                     (HPS_ENET_TX_DATA[2]),
	.hps_io_emac0_txd3                     (HPS_ENET_TX_DATA[3]),
	.hps_io_emac0_rxd0                     (HPS_ENET_RX_DATA[0]),
	.hps_io_emac0_rxd1                     (HPS_ENET_RX_DATA[1]),
	.hps_io_emac0_rxd2                     (HPS_ENET_RX_DATA[2]),
	.hps_io_emac0_rxd3                     (HPS_ENET_RX_DATA[3]),
	.hps_io_mdio0_mdio                     (HPS_ENET_MDIO),
	.hps_io_mdio0_mdc                      (HPS_ENET_MDC),
	.hps_io_sdmmc_cclk                     (HPS_SD_CLK),
	.hps_io_sdmmc_cmd                      (HPS_SD_CMD),
	.hps_io_sdmmc_data0                    (HPS_SD_DATA[0]),
	.hps_io_sdmmc_data1                    (HPS_SD_DATA[1]),
	.hps_io_sdmmc_data2                    (HPS_SD_DATA[2]),
	.hps_io_sdmmc_data3                    (HPS_SD_DATA[3]),
	.hps_io_uart1_rx                       (HPS_UART_RX),
	.hps_io_uart1_tx                       (HPS_UART_TX),
	.hps_io_usb0_clk                       (HPS_USB_CLK),
	.hps_io_usb0_stp                       (HPS_USB_STP),
	.hps_io_usb0_dir                       (HPS_USB_DIR),
	.hps_io_usb0_nxt                       (HPS_USB_NXT),
	.hps_io_usb0_data0                     (HPS_USB_DATA[0]),
	.hps_io_usb0_data1                     (HPS_USB_DATA[1]),
	.hps_io_usb0_data2                     (HPS_USB_DATA[2]),
	.hps_io_usb0_data3                     (HPS_USB_DATA[3]),
	.hps_io_usb0_data4                     (HPS_USB_DATA[4]),
	.hps_io_usb0_data5                     (HPS_USB_DATA[5]),
	.hps_io_usb0_data6                     (HPS_USB_DATA[6]),
	.hps_io_usb0_data7                     (HPS_USB_DATA[7]),
	.hps_io_i2c1_sda                       (HPS_I2C_SDA),
	.hps_io_i2c1_scl                       (HPS_I2C_SCL),
	.hps_io_gpio28                         (HPS_GSENSOR_INT),
	.hps_io_gpio34                         (HPS_GSENSOR_I2C_EN),
	.hps_io_gpio40                         (HPS_KEY),
	.hps_io_gpio41                         (HPS_LED)
);

// DE25: zweiter Chip-Select des SDRAMs komplementär zum ersten (P5,
// entschieden 2026-10-18) — wie MiSTers 128-MB-Modul: nCS=0 wählt Chip 0,
// nCS=1 Chip 1. Cores mit 64 MB halten nCS fest auf 0 (C64) und erreichen
// Chip 1 nie; MiSTer-Controller für 128 MB (Menü, Memtest, z486) schalten
// über nCS zwischen den Chips um.
assign SDRAM_nCS2 = ~SDRAM_nCS;

endmodule

/////////////////////////////////////////////////////////////////////

module sync_fix
(
	input clk,
	
	input sync_in,
	output sync_out
);

assign sync_out = sync_in ^ pol;

reg pol;
always @(posedge clk) begin
	reg [31:0] cnt;
	reg s1,s2;

	s1 <= sync_in;
	s2 <= s1;
	cnt <= s2 ? (cnt - 1) : (cnt + 1);

	if(~s2 & s1) begin
		cnt <= 0;
		pol <= cnt[31];
	end
end

endmodule

/////////////////////////////////////////////////////////////////////

// CSync generation
// Shifts HSync left by 1 HSync period during VSync

module csync
(
	input  clk,
	input  hsync,
	input  vsync,

	output csync
);

assign csync = (csync_vs ^ csync_hs);

reg csync_hs, csync_vs;
always @(posedge clk) begin
	reg prev_hs;
	reg [15:0] h_cnt, line_len, hs_len;

	// Count line/Hsync length
	h_cnt <= h_cnt + 1'd1;

	prev_hs <= hsync;
	if (prev_hs ^ hsync) begin
		h_cnt <= 0;
		if (hsync) begin
			line_len <= h_cnt - hs_len;
			csync_hs <= 0;
		end
		else hs_len <= h_cnt;
	end
	
	if (~vsync) csync_hs <= hsync;
	else if(h_cnt == line_len) csync_hs <= 1;
	
	csync_vs <= vsync;
end

endmodule
