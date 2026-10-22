// SPDX-License-Identifier: GPL-3.0-or-later
// sysmem_de25 — Ersatz für MiSTers sysmem_lite (sys/vendor/mister/sysmem.sv).
//
// Zweck:  sysmem_lite verbindet auf dem Cyclone V drei Avalon-Ports mit dem
//         DDR-Speicher des HPS (fpga2sdram), liefert den 100-MHz-Takt des
//         HPS und den Reset für den Core. Auf dem Agilex 5 gibt es diese
//         HPS-Bausteine nicht: Takt und Reset bildet dieses Modul nach, die
//         drei Speicher-Ports gehen (seit P3) als f2s_* an qsys_top. Dort
//         hängt je eine Avalon-MM Clock Crossing Bridge (Taktübergang,
//         FIFO), dahinter Platform Designers Interconnect zum AXI4-F2SDRAM
//         (sys/de25/hps_f2sdram_ports.tcl). Die Ports nach MiSTer-Seite
//         bleiben wie in sysmem_lite.
// Adressen: MiSTer gibt Wortadressen aus (ram1/ram2 64 bit, vbuf 128 bit);
//         gemeint sind Byte-Adressen 0x2000_0000–0x3FFF_FFFF. f2s_* will
//         physische Byte-Adressen. Das FPGA-Fenster ist 0xA000_0000–
//         0xBFFF_FFFF (linux/boot/retro25-bootscr.sh) — die oberen drei
//         Bits werden fest auf 101 gesetzt. So bleibt jeder Zugriff im
//         Fenster, auch wenn ein Core eine Adresse unter 0x2000_0000
//         ausgibt: er kann Linux nie überschreiben.
//         Beispiel: ram1_address 0x0600_0000 -> Byte 0x3000_0000 -> 0xB000_0000.
// Takte:  clk_100_in (100 MHz aus der PLL des HPS-Systems) wird als clock
//         ausgegeben, wie h2f_user0_clk beim Cyclone V.
// Reset:  reset_out = Reset nach dem Laden (20 ms, wie im Original),
//         HPS-System nicht bereit (hps_ninit_done), oder Wunsch von Linux
//         (reset_core_req, aus gp_out[31:30]). reset_hps_cold_req/warm_req
//         sind noch nicht angeschlossen.
// 4 KB:   Dahinter teilt avl_burst_4k Bursts an 4-KB-Grenzen — der Weg zum
//         F2SDRAM ist AXI, dort darf kein Burst eine solche Grenze kreuzen
//         (am Board: verfälschte Lesedaten beim C64-Laufwerk).
// Lesen:  ram1/ram2 lesen immer mit byteenable = FF. MiSTer-Cores lassen
//         DDRAM_BE beim Lesen oft auf dem Wert des letzten Schreibzugriffs
//         stehen (z486: main_memory); der DE10-Nano ignoriert das. Platform
//         Designer macht daraus aber einen schmalen AXI-Lesezugriff: Nur die
//         freigegebenen Bytes kamen an, der Rest war 0 (P5/Z7, Briefkasten).
// Anhalten: Vor jedem Port sitzt f2s_halt_de25. halt_req (von Linux, vor dem
//         Umladen des FPGA) hält alle drei Ports an Befehlsgrenzen an;
//         halt_idle[2:0] (vbuf, ram2, ram1; noch nicht synchronisiert) meldet,
//         wann jeder Port leer ist. Ein Port, der seit dem Laden nie
//         zugegriffen hat (z. B. ohne Takt), gilt als leer. ram1 (DDRAM des
//         Cores) wird zusätzlich beim Core-Reset angehalten, und ein vom Reset
//         abgewürgter Burst wird zu Ende gestellt — wie MiSTers
//         f2sdram_safe_terminator in sysmem.sv. Bis 20 ms nach dem Laden sind
//         alle Ports angehalten.

`default_nettype none

module sysmem_de25 #(
	parameter INIT_CYCLES = 2_000_000    // 20 ms bei 100 MHz; Testbench kürzer
)
(
	input  wire         clk_100_in,
	input  wire         hps_ninit_done,

	output wire         clock,
	output wire         reset_out,

	input  wire         reset_hps_cold_req,
	input  wire         reset_hps_warm_req,
	input  wire         reset_core_req,

	input  wire         halt_req,
	output wire   [2:0] halt_idle,

	input  wire         ram1_clk,
	input  wire  [28:0] ram1_address,
	input  wire   [7:0] ram1_burstcount,
	output wire         ram1_waitrequest,
	output wire  [63:0] ram1_readdata,
	output wire         ram1_readdatavalid,
	input  wire         ram1_read,
	input  wire  [63:0] ram1_writedata,
	input  wire   [7:0] ram1_byteenable,
	input  wire         ram1_write,

	input  wire         ram2_clk,
	input  wire  [28:0] ram2_address,
	input  wire   [7:0] ram2_burstcount,
	output wire         ram2_waitrequest,
	output wire  [63:0] ram2_readdata,
	output wire         ram2_readdatavalid,
	input  wire         ram2_read,
	input  wire  [63:0] ram2_writedata,
	input  wire   [7:0] ram2_byteenable,
	input  wire         ram2_write,

	input  wire         vbuf_clk,
	input  wire  [27:0] vbuf_address,
	input  wire   [7:0] vbuf_burstcount,
	output wire         vbuf_waitrequest,
	output wire [127:0] vbuf_readdata,
	output wire         vbuf_readdatavalid,
	input  wire         vbuf_read,
	input  wire [127:0] vbuf_writedata,
	input  wire  [15:0] vbuf_byteenable,
	input  wire         vbuf_write,

	// zu qsys_top (Avalon-MM-Master; Byte-Adressen, physisch)
	output wire         f2s_ram1_clk,
	output wire  [31:0] f2s_ram1_address,
	output wire   [7:0] f2s_ram1_burstcount,
	input  wire         f2s_ram1_waitrequest,
	input  wire  [63:0] f2s_ram1_readdata,
	input  wire         f2s_ram1_readdatavalid,
	output wire         f2s_ram1_read,
	output wire  [63:0] f2s_ram1_writedata,
	output wire   [7:0] f2s_ram1_byteenable,
	output wire         f2s_ram1_write,

	output wire         f2s_ram2_clk,
	output wire  [31:0] f2s_ram2_address,
	output wire   [7:0] f2s_ram2_burstcount,
	input  wire         f2s_ram2_waitrequest,
	input  wire  [63:0] f2s_ram2_readdata,
	input  wire         f2s_ram2_readdatavalid,
	output wire         f2s_ram2_read,
	output wire  [63:0] f2s_ram2_writedata,
	output wire   [7:0] f2s_ram2_byteenable,
	output wire         f2s_ram2_write,

	output wire         f2s_vbuf_clk,
	output wire  [31:0] f2s_vbuf_address,
	output wire   [7:0] f2s_vbuf_burstcount,
	input  wire         f2s_vbuf_waitrequest,
	input  wire [127:0] f2s_vbuf_readdata,
	input  wire         f2s_vbuf_readdatavalid,
	output wire         f2s_vbuf_read,
	output wire [127:0] f2s_vbuf_writedata,
	output wire  [15:0] f2s_vbuf_byteenable,
	output wire         f2s_vbuf_write
);

	// Byte-Adresse ins FPGA-Fenster legen: Bits 31..29 = 101
	function [31:0] window(input [31:0] byte_addr);
		window = {3'b101, byte_addr[28:0]};
	endfunction

	assign clock = clk_100_in;

	// 20 ms nach dem Laden im Reset bleiben (2 000 000 Takte, wie sysmem_lite).
	reg [20:0] init_cnt_q   = 21'd0;
	reg        init_reset_n = 1'b0;

	always @(posedge clock) begin
		if (hps_ninit_done) begin
			init_cnt_q   <= 21'd0;
			init_reset_n <= 1'b0;
		end else if (init_cnt_q < INIT_CYCLES) begin
			init_cnt_q   <= init_cnt_q + 21'd1;
			init_reset_n <= 1'b0;
		end else begin
			init_reset_n <= 1'b1;
		end
	end

	assign reset_out = ~init_reset_n | reset_core_req;

	// Speicher-Ports: über f2s_halt_de25, Adresse umgerechnet.
	assign f2s_ram1_clk = ram1_clk;
	assign f2s_ram2_clk = ram2_clk;
	assign f2s_vbuf_clk = vbuf_clk;

	// Steuersignale je Portdomäne synchronisieren
	wire init_rst = ~init_reset_n;
	wire [2:0] r1_s, r2_s, vb_s;   // {takeover, halt, rst}
	sync_2ff #(.WIDTH(3)) sync_r1(.clk(ram1_clk), .d_async({reset_out, halt_req, init_rst}), .d_sync_q(r1_s));
	sync_2ff #(.WIDTH(3)) sync_r2(.clk(ram2_clk), .d_async({1'b0,      halt_req, init_rst}), .d_sync_q(r2_s));
	sync_2ff #(.WIDTH(3)) sync_vb(.clk(vbuf_clk), .d_async({1'b0,      halt_req, init_rst}), .d_sync_q(vb_s));

	// "hat seit dem Laden zugegriffen": ohne Zugriff (oder ohne Takt) leer.
	// Ohne Startwert (Quartus-Pro-Falle 16754): Register starten nach dem
	// Laden mit 0; läuft der Takt, löscht sie zusätzlich der Init-Reset.
	reg r1_act, r2_act, vb_act;
	always @(posedge ram1_clk)
		if (r1_s[0]) r1_act <= 1'b0; else if (f2s_ram1_read | f2s_ram1_write) r1_act <= 1'b1;
	always @(posedge ram2_clk)
		if (r2_s[0]) r2_act <= 1'b0; else if (f2s_ram2_read | f2s_ram2_write) r2_act <= 1'b1;
	always @(posedge vbuf_clk)
		if (vb_s[0]) vb_act <= 1'b0; else if (f2s_vbuf_read | f2s_vbuf_write) vb_act <= 1'b1;

	wire r1_idle, r2_idle, vb_idle;
	assign halt_idle = {vb_idle | ~vb_act, r2_idle | ~r2_act, r1_idle | ~r1_act};

	// Ausgang von halt_ram1, dann Bursts an 4-KB-Grenzen teilen (AXI-Regel)
	wire [31:0] h_ram1_address;
	wire  [7:0] h_ram1_burstcount;
	wire        h_ram1_read, h_ram1_write, h_ram1_waitrequest, h_ram1_readdatavalid;
	wire [63:0] h_ram1_writedata, h_ram1_readdata;
	wire [7:0] h_ram1_byteenable;
	f2s_halt_de25 #(.DW(64), .TAKEOVER(1)) halt_ram1 (
		.clk(ram1_clk), .rst(r1_s[0]), .halt(r1_s[1]), .takeover(r1_s[2]), .idle(r1_idle),
		.s_address(window({ram1_address, 3'b000})), .s_burstcount(ram1_burstcount),
		.s_read(ram1_read), .s_write(ram1_write), .s_writedata(ram1_writedata),
		.s_byteenable(ram1_byteenable), .s_waitrequest(ram1_waitrequest),
		.s_readdata(ram1_readdata), .s_readdatavalid(ram1_readdatavalid),
		.m_address(h_ram1_address), .m_burstcount(h_ram1_burstcount),
		.m_read(h_ram1_read), .m_write(h_ram1_write), .m_writedata(h_ram1_writedata),
		.m_byteenable(h_ram1_byteenable), .m_waitrequest(h_ram1_waitrequest),
		.m_readdata(h_ram1_readdata), .m_readdatavalid(h_ram1_readdatavalid)
	);

	avl_burst_4k #(.DW(64)) split_ram1 (
		.clk(ram1_clk), .rst(r1_s[0]),
		.s_address(h_ram1_address), .s_burstcount(h_ram1_burstcount),
		.s_read(h_ram1_read), .s_write(h_ram1_write), .s_writedata(h_ram1_writedata),
		.s_byteenable(h_ram1_read ? 8'hFF : h_ram1_byteenable), .s_waitrequest(h_ram1_waitrequest),
		.s_readdata(h_ram1_readdata), .s_readdatavalid(h_ram1_readdatavalid),
		.m_address(f2s_ram1_address), .m_burstcount(f2s_ram1_burstcount),
		.m_read(f2s_ram1_read), .m_write(f2s_ram1_write), .m_writedata(f2s_ram1_writedata),
		.m_byteenable(f2s_ram1_byteenable), .m_waitrequest(f2s_ram1_waitrequest),
		.m_readdata(f2s_ram1_readdata), .m_readdatavalid(f2s_ram1_readdatavalid)
	);

	// Ausgang von halt_ram2, dann Bursts an 4-KB-Grenzen teilen (AXI-Regel)
	wire [31:0] h_ram2_address;
	wire  [7:0] h_ram2_burstcount;
	wire        h_ram2_read, h_ram2_write, h_ram2_waitrequest, h_ram2_readdatavalid;
	wire [63:0] h_ram2_writedata, h_ram2_readdata;
	wire [7:0] h_ram2_byteenable;
	f2s_halt_de25 #(.DW(64), .TAKEOVER(0)) halt_ram2 (
		.clk(ram2_clk), .rst(r2_s[0]), .halt(r2_s[1]), .takeover(r2_s[2]), .idle(r2_idle),
		.s_address(window({ram2_address, 3'b000})), .s_burstcount(ram2_burstcount),
		.s_read(ram2_read), .s_write(ram2_write), .s_writedata(ram2_writedata),
		.s_byteenable(ram2_byteenable), .s_waitrequest(ram2_waitrequest),
		.s_readdata(ram2_readdata), .s_readdatavalid(ram2_readdatavalid),
		.m_address(h_ram2_address), .m_burstcount(h_ram2_burstcount),
		.m_read(h_ram2_read), .m_write(h_ram2_write), .m_writedata(h_ram2_writedata),
		.m_byteenable(h_ram2_byteenable), .m_waitrequest(h_ram2_waitrequest),
		.m_readdata(h_ram2_readdata), .m_readdatavalid(h_ram2_readdatavalid)
	);

	avl_burst_4k #(.DW(64)) split_ram2 (
		.clk(ram2_clk), .rst(r2_s[0]),
		.s_address(h_ram2_address), .s_burstcount(h_ram2_burstcount),
		.s_read(h_ram2_read), .s_write(h_ram2_write), .s_writedata(h_ram2_writedata),
		.s_byteenable(h_ram2_read ? 8'hFF : h_ram2_byteenable), .s_waitrequest(h_ram2_waitrequest),
		.s_readdata(h_ram2_readdata), .s_readdatavalid(h_ram2_readdatavalid),
		.m_address(f2s_ram2_address), .m_burstcount(f2s_ram2_burstcount),
		.m_read(f2s_ram2_read), .m_write(f2s_ram2_write), .m_writedata(f2s_ram2_writedata),
		.m_byteenable(f2s_ram2_byteenable), .m_waitrequest(f2s_ram2_waitrequest),
		.m_readdata(f2s_ram2_readdata), .m_readdatavalid(f2s_ram2_readdatavalid)
	);

	// Ausgang von halt_vbuf, dann Bursts an 4-KB-Grenzen teilen (AXI-Regel)
	wire [31:0] h_vbuf_address;
	wire  [7:0] h_vbuf_burstcount;
	wire        h_vbuf_read, h_vbuf_write, h_vbuf_waitrequest, h_vbuf_readdatavalid;
	wire [127:0] h_vbuf_writedata, h_vbuf_readdata;
	wire [15:0] h_vbuf_byteenable;
	f2s_halt_de25 #(.DW(128), .TAKEOVER(0)) halt_vbuf (
		.clk(vbuf_clk), .rst(vb_s[0]), .halt(vb_s[1]), .takeover(vb_s[2]), .idle(vb_idle),
		.s_address(window({vbuf_address, 4'b0000})), .s_burstcount(vbuf_burstcount),
		.s_read(vbuf_read), .s_write(vbuf_write), .s_writedata(vbuf_writedata),
		.s_byteenable(vbuf_byteenable), .s_waitrequest(vbuf_waitrequest),
		.s_readdata(vbuf_readdata), .s_readdatavalid(vbuf_readdatavalid),
		.m_address(h_vbuf_address), .m_burstcount(h_vbuf_burstcount),
		.m_read(h_vbuf_read), .m_write(h_vbuf_write), .m_writedata(h_vbuf_writedata),
		.m_byteenable(h_vbuf_byteenable), .m_waitrequest(h_vbuf_waitrequest),
		.m_readdata(h_vbuf_readdata), .m_readdatavalid(h_vbuf_readdatavalid)
	);

	avl_burst_4k #(.DW(128)) split_vbuf (
		.clk(vbuf_clk), .rst(vb_s[0]),
		.s_address(h_vbuf_address), .s_burstcount(h_vbuf_burstcount),
		.s_read(h_vbuf_read), .s_write(h_vbuf_write), .s_writedata(h_vbuf_writedata),
		.s_byteenable(h_vbuf_byteenable), .s_waitrequest(h_vbuf_waitrequest),
		.s_readdata(h_vbuf_readdata), .s_readdatavalid(h_vbuf_readdatavalid),
		.m_address(f2s_vbuf_address), .m_burstcount(f2s_vbuf_burstcount),
		.m_read(f2s_vbuf_read), .m_write(f2s_vbuf_write), .m_writedata(f2s_vbuf_writedata),
		.m_byteenable(f2s_vbuf_byteenable), .m_waitrequest(f2s_vbuf_waitrequest),
		.m_readdata(f2s_vbuf_readdata), .m_readdatavalid(f2s_vbuf_readdatavalid)
	);

endmodule

`default_nettype wire
