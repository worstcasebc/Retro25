// SPDX-License-Identifier: GPL-3.0-or-later
// avl_burst_4k — teilt Avalon-MM-Bursts an 4-KB-Grenzen (Retro25).
//
// Zweck:  Hinter den DDR-Ports geht es über Platform Designer als AXI4 zum
//         F2SDRAM. Ein AXI-Burst darf keine 4-KB-Grenze kreuzen; MiSTer-Cores
//         kennen diese Regel nicht (auf dem Cyclone V gibt es sie nicht). Am
//         Board kam beim C64 der Teil eines Lese-Bursts hinter der Grenze
//         verfälscht an (Disketten-Sektoren über einer 4-KB-Grenze). Platform
//         Designer teilt solche Bursts hier nicht selbst auf.
// Takt:   ein Takt (der des Ports), Reset synchron, aktiv high.
// Schnittstelle: Avalon-MM mit waitrequest, readdatavalid und burstcount
//         (Byte-Adressen, Wortbreite DW), s_* zum Master, m_* zum Slave.
// Verhalten:
//   - Lesen: Ein Befehl, der eine Grenze kreuzt, wird zu zwei Befehlen (bis
//     zur Grenze, Rest ab der Grenze). Der Master bleibt per waitrequest
//     stehen, bis beide angenommen sind. Die Daten kommen in Reihenfolge und
//     unverändert durch.
//   - Schreiben: Der erste Beat geht mit der Länge bis zur Grenze hinaus; der
//     Beat an der Grenze beginnt einen neuen Burst (Adresse = Grenze, Länge =
//     Rest). Der Master merkt davon nichts.
//   - Bursts ohne Grenze gehen unverändert und ohne zusätzlichen Takt durch.
//   Annahmen (Avalon): Adressen auf Wortgrenzen; ein Schreib-Burst wird zu
//   Ende geschrieben, bevor der Master etwas anderes beginnt.

`default_nettype none

module avl_burst_4k #(
	parameter DW = 64,                 // Datenbreite in Bit (64 oder 128)
	parameter AW = 32,                 // Byte-Adresse
	parameter BW = 8                   // Breite burstcount
)
(
	input  wire          clk,
	input  wire          rst,

	input  wire [AW-1:0] s_address,
	input  wire [BW-1:0] s_burstcount,
	input  wire          s_read,
	input  wire          s_write,
	input  wire [DW-1:0] s_writedata,
	input  wire [DW/8-1:0] s_byteenable,
	output wire          s_waitrequest,
	output wire [DW-1:0] s_readdata,
	output wire          s_readdatavalid,

	output wire [AW-1:0] m_address,
	output wire [BW-1:0] m_burstcount,
	output wire          m_read,
	output wire          m_write,
	output wire [DW-1:0] m_writedata,
	output wire [DW/8-1:0] m_byteenable,
	input  wire          m_waitrequest,
	input  wire [DW-1:0] m_readdata,
	input  wire          m_readdatavalid
);

localparam LB = (DW == 128) ? 4 : 3;   // log2(Bytes je Wort)

// Wörter bis zur nächsten 4-KB-Grenze und erste Adresse dahinter
wire [12:0]   room_bytes = 13'd4096 - {1'b0, s_address[11:0]};
wire [12:0]   room       = room_bytes >> LB;             // 1 .. 4096/Bytes
wire          crosses    = {5'd0, s_burstcount} > room;
wire [BW-1:0] len1       = room[BW-1:0];                 // gilt nur bei crosses
wire [AW-1:0] boundary   = {s_address[AW-1:12] + 1'b1, 12'd0};

// ---- Lesen: zweiter Befehl ausstehend --------------------------------------
reg          rd2_q;
reg [AW-1:0] rd2_addr_q;
reg [BW-1:0] rd2_len_q;

// ---- Schreiben: laufender Burst ---------------------------------------------
reg          wr_busy_q;                // im Burst (nach dem ersten Beat)
reg [BW-1:0] wr_left_q;                // Beats im aktuellen Ausgangs-Burst übrig
reg [BW-1:0] wr_rest_q;                // Beats des zweiten Teils (0 = keiner)
reg [AW-1:0] wr_addr2_q;

wire wr_first = s_write && !wr_busy_q;                   // erster Beat eines Bursts
wire wr_seg2  = s_write &&  wr_busy_q && (wr_left_q == 0); // erster Beat des Rests

assign m_read       = rd2_q | (s_read & ~wr_busy_q);
assign m_write      = s_write & ~rd2_q;
assign m_address    = rd2_q    ? rd2_addr_q :
                      wr_seg2  ? wr_addr2_q : s_address;
assign m_burstcount = rd2_q    ? rd2_len_q  :
                      wr_seg2  ? wr_rest_q  :
                      crosses  ? len1       : s_burstcount;
assign m_writedata  = s_writedata;
assign m_byteenable = s_byteenable;

// Lesebefehl mit Grenze: erst der zweite Teil gibt den Master frei
assign s_waitrequest = rd2_q ? m_waitrequest :
                       (s_read & crosses) ? 1'b1 : m_waitrequest;

assign s_readdata      = m_readdata;
assign s_readdatavalid = m_readdatavalid;

wire acc = ~m_waitrequest;             // Ausgang nimmt in diesem Takt an

always @(posedge clk) begin
	if (rst) begin
		rd2_q     <= 1'b0;
		wr_busy_q <= 1'b0;
		wr_left_q <= {BW{1'b0}};
		wr_rest_q <= {BW{1'b0}};
	end else begin
		// Lesen
		if (rd2_q) begin
			if (acc) rd2_q <= 1'b0;
		end else if (s_read && crosses && acc) begin
			rd2_q      <= 1'b1;
			rd2_addr_q <= boundary;
			rd2_len_q  <= s_burstcount - len1;
		end

		// Schreiben (Beat angenommen)
		if (m_write && acc) begin
			if (wr_first) begin
				if (crosses) begin
					wr_busy_q  <= 1'b1;
					wr_left_q  <= len1 - 1'b1;
					wr_rest_q  <= s_burstcount - len1;
					wr_addr2_q <= boundary;
				end else begin
					wr_busy_q  <= (s_burstcount > 1);
					wr_left_q  <= s_burstcount - 1'b1;
					wr_rest_q  <= {BW{1'b0}};
				end
			end else if (wr_seg2) begin
				wr_left_q <= wr_rest_q - 1'b1;
				wr_rest_q <= {BW{1'b0}};
				if (wr_rest_q == 1) wr_busy_q <= 1'b0;
			end else begin
				wr_left_q <= wr_left_q - 1'b1;
				if (wr_left_q == 1 && wr_rest_q == 0) wr_busy_q <= 1'b0;
			end
		end
	end
end

endmodule

`default_nettype wire
