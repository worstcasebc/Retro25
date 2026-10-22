// SPDX-License-Identifier: GPL-3.0-or-later
// avl_slow_cdc — einzelne Avalon-Zugriffe in eine andere Taktdomäne tragen.
//
// Zweck:  Linux (LW-Bridge, clk_a) liest/schreibt Register, die in einer
//         anderen Domäne (clk_b) liegen — hier die Debug-Register von
//         pll_cfg_de25 und später der I2C-Master. Für seltene Zugriffe, nicht
//         für Durchsatz: ein Zugriff kostet rund 10 Takte.
// Ablauf: Seite A hält den Zugriff mit waitrequest an, merkt sich Adresse
//         und Daten und kippt req. Seite B sieht das Kippen (2 FF), gibt
//         einen Takt b_write bzw. b_read aus, übernimmt im Takt danach
//         b_readdata und kippt ack. Seite A sieht ack (2 FF), nimmt
//         waitrequest weg und liefert bei Lesezugriffen einen Takt später
//         readdatavalid. Adresse/Daten bleiben während des Handshakes stabil,
//         daher dürfen sie als Bündel die Domäne wechseln.
// Takte:  clk_a (Avalon-Slave), clk_b (einfacher Registerport, Lesedaten
//         einen Takt nach b_read gültig). Synchronizer: *meta_q* (SDC).
// Analogie: Eine Durchreiche zwischen zwei Küchen mit Klingel hin und zurück.

`default_nettype none

module avl_slow_cdc #(
	parameter AW = 14
) (
	input  wire          clk_a,
	input  wire          rst_a,
	input  wire [AW-1:0] a_address,
	input  wire          a_write,
	input  wire   [31:0] a_writedata,
	input  wire          a_read,
	output wire          a_waitrequest,
	output reg    [31:0] a_readdata,
	output reg           a_readdatavalid,

	input  wire          clk_b,
	output reg  [AW-1:0] b_address,
	output reg           b_write,
	output reg    [31:0] b_writedata,
	output reg           b_read,
	input  wire   [31:0] b_readdata
);

	// --- Seite A -------------------------------------------------------------
	reg          req_q = 1'b0;
	reg          ack_seen_q = 1'b0;
	reg          ack_meta_q = 1'b0, ack_s_q = 1'b0;
	reg  [1:0]   st_a = 2'd0;          // 0 frei, 1 warten, 2 fertig
	reg [AW-1:0] addr_q;
	reg   [31:0] wdata_q;
	reg          rd_q;
	reg   [31:0] rdata_b_q;            // Lesedaten aus Seite B (stabil bei ack)

	assign a_waitrequest = (a_read | a_write) & (st_a != 2'd2);

	always @(posedge clk_a) begin
		ack_meta_q <= ack_q;
		ack_s_q    <= ack_meta_q;
		a_readdatavalid <= 1'b0;
		if (rst_a) begin
			st_a <= 2'd0;
			ack_seen_q <= ack_s_q;
		end else case (st_a)
			2'd0: if (a_read | a_write) begin
				addr_q  <= a_address;
				wdata_q <= a_writedata;
				rd_q    <= a_read;
				req_q   <= ~req_q;
				st_a    <= 2'd1;
			end
			2'd1: if (ack_s_q != ack_seen_q) begin
				ack_seen_q <= ack_s_q;
				st_a <= 2'd2;
			end
			default: begin   // Zugriff in diesem Takt angenommen
				a_readdata      <= rdata_b_q;
				a_readdatavalid <= rd_q;
				st_a <= 2'd0;
			end
		endcase
	end

	// --- Seite B -------------------------------------------------------------
	reg       req_meta_q = 1'b0, req_s_q = 1'b0, req_seen_q = 1'b0;
	reg       ack_q = 1'b0;
	reg [1:0] st_b = 2'd0;

	always @(posedge clk_b) begin
		req_meta_q <= req_q;
		req_s_q    <= req_meta_q;
		b_write <= 1'b0;
		b_read  <= 1'b0;
		case (st_b)
			2'd0: if (req_s_q != req_seen_q) begin
				req_seen_q  <= req_s_q;
				b_address   <= addr_q;
				b_writedata <= wdata_q;
				b_write     <= ~rd_q;
				b_read      <= rd_q;
				st_b <= 2'd1;
			end
			2'd1: st_b <= 2'd2;            // Slave übernimmt / registriert Lesedaten
			default: begin
				rdata_b_q <= b_readdata;
				ack_q <= ~ack_q;
				st_b <= 2'd0;
			end
		endcase
	end

endmodule

`default_nettype wire
