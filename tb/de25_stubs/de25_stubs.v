// SPDX-License-Identifier: GPL-3.0-or-later
// de25_stubs — Simulationsmodelle für die Quartus-IPs um sys_top_de25.
//
// pll, pll_tp, pll_audio: erzeugen nur den Ausgangstakt (keine Phase, kein
//                         Einschwingen); locked geht nach 1 µs auf 1.
// qsys_top:               das HPS-System. ninit_done fällt nach 200 ns.
//                         Die Brücke c64_m0 ist ein Avalon-Master, den die
//                         Testbench über die Aufgaben av_write/av_read
//                         bedient (Byte-Adresse im 16-Byte-Fenster).

`timescale 1ps/1ps

module pll (input wire refclk, input wire rst, output reg outclk_0 = 1'b0, output wire locked);
	always #5000 outclk_0 = ~outclk_0;                    // 100 MHz
	reg l = 1'b0; initial #1_000_000 l = 1'b1; assign locked = l;
endmodule

module pll_tp (input wire refclk, input wire rst, output reg outclk_0 = 1'b0, output wire locked);
	always #6734 outclk_0 = ~outclk_0;                    // 74,25 MHz (13,468 ns)
	reg l = 1'b0; initial #1_000_000 l = 1'b1; assign locked = l;
endmodule

module pll_audio (input wire refclk, input wire rst, output reg outclk_0 = 1'b0);
	always #20345 outclk_0 = ~outclk_0;                   // 24,576 MHz
endmodule

module qsys_top (
	input  wire        disk_m0_waitrequest,
	input  wire [31:0] disk_m0_readdata,
	input  wire        disk_m0_readdatavalid,
	output wire  [0:0] disk_m0_burstcount,
	output wire [31:0] disk_m0_writedata,
	output wire [13:0] disk_m0_address,
	output wire        disk_m0_write,
	output wire        disk_m0_read,
	output wire  [3:0] disk_m0_byteenable,
	output wire        disk_m0_debugaccess,
	input  wire        c64_m0_waitrequest,
	input  wire [31:0] c64_m0_readdata,
	input  wire        c64_m0_readdatavalid,
	output wire  [0:0] c64_m0_burstcount,
	output reg  [31:0] c64_m0_writedata = 32'd0,
	output reg   [3:0] c64_m0_address = 4'd0,
	output reg         c64_m0_write = 1'b0,
	output reg         c64_m0_read = 1'b0,
	output reg   [3:0] c64_m0_byteenable = 4'hF,
	output wire        c64_m0_debugaccess,
	input  wire        clk_100_clk,
	input  wire        reset_reset_n,
	output reg         ninit_done_ninit_done = 1'b1,
	input  wire  [2:0] led_pio_external_connection_in_port,
	output wire  [2:0] led_pio_external_connection_out_port,
	input  wire  [3:0] dipsw_pio_external_connection_export,
	input  wire  [3:0] button_pio_external_connection_export,
	input  wire        hps_io_hps_osc_clk,
	output wire        emif_hps_emif_mem_0_mem_cs,
	output wire  [5:0] emif_hps_emif_mem_0_mem_ca,
	output wire        emif_hps_emif_mem_0_mem_cke,
	inout  wire [31:0] emif_hps_emif_mem_0_mem_dq,
	inout  wire  [3:0] emif_hps_emif_mem_0_mem_dqs_t,
	inout  wire  [3:0] emif_hps_emif_mem_0_mem_dqs_c,
	inout  wire  [3:0] emif_hps_emif_mem_0_mem_dmi,
	output wire        emif_hps_emif_mem_ck_0_mem_ck_t,
	output wire        emif_hps_emif_mem_ck_0_mem_ck_c,
	output wire        emif_hps_emif_mem_reset_n_mem_reset_n,
	input  wire        emif_hps_emif_oct_0_oct_rzqin,
	input  wire        emif_hps_emif_ref_clk_0_clk,
	output wire        hps_io_emac0_tx_clk,
	input  wire        hps_io_emac0_rx_clk,
	output wire        hps_io_emac0_tx_ctl,
	input  wire        hps_io_emac0_rx_ctl,
	output wire        hps_io_emac0_txd0, hps_io_emac0_txd1, hps_io_emac0_txd2, hps_io_emac0_txd3,
	input  wire        hps_io_emac0_rxd0, hps_io_emac0_rxd1, hps_io_emac0_rxd2, hps_io_emac0_rxd3,
	inout  wire        hps_io_mdio0_mdio,
	output wire        hps_io_mdio0_mdc,
	output wire        hps_io_sdmmc_cclk,
	inout  wire        hps_io_sdmmc_cmd,
	inout  wire        hps_io_sdmmc_data0, hps_io_sdmmc_data1, hps_io_sdmmc_data2, hps_io_sdmmc_data3,
	input  wire        hps_io_uart1_rx,
	output wire        hps_io_uart1_tx,
	input  wire        hps_io_usb0_clk,
	output wire        hps_io_usb0_stp,
	input  wire        hps_io_usb0_dir,
	input  wire        hps_io_usb0_nxt,
	inout  wire        hps_io_usb0_data0, hps_io_usb0_data1, hps_io_usb0_data2, hps_io_usb0_data3,
	inout  wire        hps_io_usb0_data4, hps_io_usb0_data5, hps_io_usb0_data6, hps_io_usb0_data7,
	inout  wire        hps_io_i2c1_sda,
	inout  wire        hps_io_i2c1_scl,
	inout  wire        hps_io_gpio28, hps_io_gpio34, hps_io_gpio40, hps_io_gpio41
);
	initial #200_000 ninit_done_ninit_done = 1'b0;

	assign disk_m0_burstcount = 1'b1;
	assign disk_m0_writedata  = 32'd0;
	assign disk_m0_address    = 14'd0;
	assign disk_m0_write      = 1'b0;
	assign disk_m0_read       = 1'b0;
	assign disk_m0_byteenable = 4'hF;
	assign c64_m0_burstcount  = 1'b1;
	assign led_pio_external_connection_out_port = 3'd0;

	// Avalon-Master wie die LW-Bridge: Zugriff hält, solange waitrequest = 1.
	task av_write(input [3:0] addr, input [31:0] data);
		begin
			@(negedge clk_100_clk);
			c64_m0_address = addr; c64_m0_writedata = data; c64_m0_write = 1'b1;
			#1;
			while (c64_m0_waitrequest) @(negedge clk_100_clk);
			@(posedge clk_100_clk);
			#1 c64_m0_write = 1'b0;
		end
	endtask

	task av_read(input [3:0] addr, output [31:0] data);
		begin
			@(negedge clk_100_clk);
			c64_m0_address = addr; c64_m0_read = 1'b1;
			@(posedge clk_100_clk);
			#1 c64_m0_read = 1'b0;
			while (!c64_m0_readdatavalid) @(posedge clk_100_clk) #1;
			data = c64_m0_readdata;
		end
	endtask
endmodule

// hps_io (nur Simulation): MiSTers hps_io.sv nutzt Bezeichner vor ihrer
// Deklaration — Quartus nimmt das hin, Questa nicht. Dieses Modell erfüllt
// nur, was sys_top braucht: clk_sys auf HPS_BUS[36], io_wait = 0, keine
// Antworten (io_dout = 0, nicht WIDE). Das echte hps_io prüft Quartus.
module hps_io #(parameter CONF_STR = "", WIDE = 0)
(
	input  wire         clk_sys,
	inout  wire  [45:0] HPS_BUS,
	inout  wire  [35:0] EXT_BUS,
	output wire  [21:0] gamma_bus,
	output wire   [1:0] buttons,
	output wire [127:0] status,
	input  wire  [15:0] status_menumask
);
	assign HPS_BUS[37]   = 1'b0;        // io_wait
	assign HPS_BUS[36]   = clk_sys;
	assign HPS_BUS[32]   = 1'b0;        // io_wide
	assign HPS_BUS[15:0] = 16'd0;       // io_dout
	assign buttons = 2'b00;
	assign status  = 128'd0;
endmodule

// audio_out, ddr_svc (nur Simulation): wie hps_io von Questa abgelehnt
// (Bezeichner vor ihrer Deklaration). Für die Bild- und Brückentests nicht
// nötig: Ausgänge fest auf Ruhe.
module audio_out (
	input wire reset, input wire clk, input wire sample_rate,
	input wire [31:0] flt_rate, input wire [39:0] cx, input wire [7:0] cx0, cx1, cx2,
	input wire [23:0] cy0, cy1, cy2, input wire [4:0] att, input wire [1:0] boost, mix,
	input wire is_signed, input wire [15:0] core_l, core_r, alsa_l, alsa_r,
	output wire i2s_bclk, i2s_lrclk, i2s_data, spdif, dac_l, dac_r
);
	assign {i2s_bclk, i2s_lrclk, i2s_data, spdif, dac_l, dac_r} = 6'd0;
endmodule

module ddr_svc (
	input wire clk, input wire ram_waitrequest, output wire [7:0] ram_burstcnt,
	output wire [28:0] ram_addr, input wire [63:0] ram_readdata, input wire ram_read_ready,
	output reg ram_read = 1'b0, output wire [63:0] ram_writedata, output wire [7:0] ram_byteenable,
	output reg ram_write = 1'b0, output wire [7:0] ram_bcnt,
	input wire [31:3] ch0_addr, input wire [7:0] ch0_burst, output wire [63:0] ch0_data,
	input wire ch0_req, output wire ch0_ready,
	input wire [31:3] ch1_addr, input wire [7:0] ch1_burst, output wire [63:0] ch1_data,
	input wire ch1_req, output wire ch1_ready
);
	assign ram_burstcnt = 8'd0; assign ram_addr = 29'd0; assign ram_writedata = 64'd0;
	assign ram_byteenable = 8'd0; assign ram_bcnt = 8'd0;
	assign ch0_data = 64'd0; assign ch0_ready = 1'b0; assign ch1_data = 64'd0; assign ch1_ready = 1'b0;
endmodule
