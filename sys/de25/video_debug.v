// SPDX-License-Identifier: GPL-3.0-or-later
// video_debug — Messpunkte der Videokette, lesbar von Linux (P3, Fehlersuche).
//
// Zweck:  Zählt Flanken an Stellen der Videokette (Core-Ausgang, ascal-Ein-
//         und -Ausgang, HDMI-Pins) und Zugriffe auf den vbuf-Port, jeweils
//         in der Taktdomäne des Signals. Dazu Statusbits und das Timing, das
//         Main geschickt hat. Linux liest die Werte über die LW-Bridge
//         (disk_m0, physisch 0x2001_4000, nur lesen):
//           0x00  ID 0x5232_3544 ("R25D")
//           0x04  Bildanfänge (VS steigend) am Core-Ausgang     clk_vid
//           0x08  Zeilen mit DE (DE steigend) am Core-Ausgang   clk_vid
//           0x0C  Zeilen mit DE am ascal-Eingang (ce = 1)      clk_vid
//           0x10  Bildanfänge am ascal-Ausgang (o_vs)          clk_hdmi
//           0x14  Zeilen mit DE am ascal-Ausgang               clk_hdmi
//           0x18  Takte von clk_hdmi / 1024                     clk_hdmi
//           0x1C  vbuf: angenommene Schreibwörter               clk_vbuf
//           0x20  vbuf: angenommene Lesebefehle                 clk_vbuf
//           0x24  vbuf: Lesewörter zurück (readdatavalid)       clk_vbuf
//           0x28  vbuf: Takte mit waitrequest bei Anfrage       clk_vbuf
//           0x2C  Statusbits status (Bedeutung in sys_top_de25.v)
//           0x30  info0 (frei belegbar, z. B. {HEIGHT, WIDTH})
//           0x34  info1
// Takte:  Zähler in ihrer Domäne; clk_av (LW-Bridge) liest jeden Zähler über
//         zwei Flipflops (erste Stufe "*meta_q*", von der SDC ausgenommen).
//         Mehrbit-Werte können beim Weiterzählen einmal falsch gelesen werden
//         — für "läuft es oder steht es" genügt das (kein Gray-Code nötig).
// Analogie: Lichtschranken entlang eines Förderbands: Man sieht, bis zu
//         welcher Station noch Pakete ankommen.

`default_nettype none

module video_debug (
	input  wire        clk_av,
	input  wire [13:0] avs_address,
	input  wire        avs_read,
	output reg  [31:0] avs_readdata,
	output reg         avs_readdatavalid,

	input  wire        clk_vid,
	input  wire        core_vs,
	input  wire        core_de,
	input  wire        in_ce,
	input  wire        in_de,

	input  wire        clk_hdmi,
	input  wire        out_vs,
	input  wire        out_de,

	input  wire        clk_vbuf,
	input  wire        vbuf_write,
	input  wire        vbuf_read,
	input  wire        vbuf_waitrequest,
	input  wire        vbuf_readdatavalid,

	input  wire [31:0] status,
	input  wire [31:0] info0,
	input  wire [31:0] info1
);

	// --- Zähler in clk_vid ---------------------------------------------------
	reg        core_vs_q = 0, core_de_q = 0, in_de_q = 0;
	reg [31:0] cnt_core_vs = 0, cnt_core_de = 0, cnt_in_de = 0;
	always @(posedge clk_vid) begin
		core_vs_q <= core_vs;
		core_de_q <= core_de;
		if (core_vs & ~core_vs_q) cnt_core_vs <= cnt_core_vs + 1'd1;
		if (core_de & ~core_de_q) cnt_core_de <= cnt_core_de + 1'd1;
		if (in_ce) begin
			in_de_q <= in_de;
			if (in_de & ~in_de_q) cnt_in_de <= cnt_in_de + 1'd1;
		end
	end

	// --- Zähler in clk_hdmi --------------------------------------------------
	reg        out_vs_q = 0, out_de_q = 0;
	reg [31:0] cnt_out_vs = 0, cnt_out_de = 0;
	reg [41:0] cnt_hdmi_clk = 0;
	always @(posedge clk_hdmi) begin
		out_vs_q <= out_vs;
		out_de_q <= out_de;
		if (out_vs & ~out_vs_q) cnt_out_vs <= cnt_out_vs + 1'd1;
		if (out_de & ~out_de_q) cnt_out_de <= cnt_out_de + 1'd1;
		cnt_hdmi_clk <= cnt_hdmi_clk + 1'd1;
	end

	// --- Zähler in clk_vbuf --------------------------------------------------
	reg [31:0] cnt_vb_wr = 0, cnt_vb_rd = 0, cnt_vb_rdv = 0, cnt_vb_wait = 0;
	always @(posedge clk_vbuf) begin
		if (vbuf_write & ~vbuf_waitrequest) cnt_vb_wr <= cnt_vb_wr + 1'd1;
		if (vbuf_read  & ~vbuf_waitrequest) cnt_vb_rd <= cnt_vb_rd + 1'd1;
		if (vbuf_readdatavalid)             cnt_vb_rdv <= cnt_vb_rdv + 1'd1;
		if ((vbuf_write | vbuf_read) & vbuf_waitrequest) cnt_vb_wait <= cnt_vb_wait + 1'd1;
	end

	// --- Lesen in clk_av: alle Werte über zwei Flipflops ---------------------
	localparam N = 14;
	wire [32*N-1:0] values = {
		info1, info0, status,
		cnt_vb_wait, cnt_vb_rdv, cnt_vb_rd, cnt_vb_wr,
		cnt_hdmi_clk[41:10], cnt_out_de, cnt_out_vs,
		cnt_in_de, cnt_core_de, cnt_core_vs,
		32'h5232_3544
	};
	reg [32*N-1:0] values_meta_q = 0, values_q = 0;
	always @(posedge clk_av) begin
		values_meta_q <= values;
		values_q      <= values_meta_q;
	end

	always @(posedge clk_av) begin
		avs_readdatavalid <= avs_read;
		if (avs_read)
			avs_readdata <= (avs_address[13:2] < N) ? values_q[avs_address[13:2]*32 +: 32] : 32'd0;
	end

endmodule

`default_nettype wire
