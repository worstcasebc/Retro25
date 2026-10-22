// SPDX-License-Identifier: GPL-3.0-or-later
// ddr_test — Speichertest über MiSTers DDRAM-Port (P3, Schritt 2c).
//
// Zweck:  Schreibt WORDS 64-bit-Wörter ab BASE in Bursts zu BURST Wörtern,
//         liest sie in Bursts zurück und vergleicht. Ergebnis: done_q, pass_q,
//         Fehlerzahl err_q, Takte fürs Schreiben (wr_cycles_q) und Lesen
//         (rd_cycles_q) — daraus die Bandbreite. Das Muster lässt sich danach
//         auch von Linux aus prüfen (/dev/mem, physisch BASE*8 | 0xA000_0000).
//         Muster je Wort i: {i ^ 32'hA5A5_5A5A, i ^ seed} — seed wechselt mit
//         jedem Lauf, damit ein alter Inhalt nicht als Erfolg durchgeht.
// Takt:   clk (= DDRAM_CLK des Cores), synchroner Reset rst (aktiv high);
//         ein laufender Burst bzw. wartender Befehl wird auch im Reset
//         zu Ende gebracht (Avalon-Regel, siehe unten).
// Schnittstelle: DDRAM_* wie in MiSTers emu (Avalon-MM, Wortadresse
//         64 bit, busy = waitrequest, burstcnt mit dem ersten Wort);
//         start = Puls, startet einen Lauf (auch erneut).
// Analogie: Wir füllen eine Regalreihe mit nummerierten Kisten, gehen dann
//         die Reihe noch einmal ab und schauen, ob jede Nummer stimmt.

`default_nettype none

module ddr_test #(
	parameter [28:0] BASE  = 29'h0600_0000,   // Byte 0x3000_0000 (MiSTer-DDRAM)
	parameter        WORDS = 16384,           // 128 KB
	parameter        BURST = 64               // Wörter je Burst (<= 128)
) (
	input  wire        clk,
	input  wire        rst,
	input  wire        start,

	output reg  [28:0] ddram_addr,
	output reg   [7:0] ddram_burstcnt,
	input  wire        ddram_busy,
	input  wire [63:0] ddram_dout,
	input  wire        ddram_dout_ready,
	output reg         ddram_rd,
	output reg  [63:0] ddram_din,
	output wire  [7:0] ddram_be,
	output reg         ddram_we,

	output reg         running_q,
	output reg         done_q,
	output reg         pass_q,
	output reg  [15:0] err_q,
	output reg  [31:0] wr_cycles_q,
	output reg  [31:0] rd_cycles_q
);

	localparam AW = $clog2(WORDS);
	localparam [8:0] BURST9 = BURST;
	localparam S_IDLE = 3'd0, S_WR = 3'd1, S_RD_CMD = 3'd2, S_RD_DATA = 3'd3, S_DONE = 3'd4;

	reg  [2:0]  state_q;
	reg  [AW:0] idx_q;        // nächstes zu schreibendes bzw. anzufordernde Wort
	reg  [AW:0] chk_q;        // nächstes zu prüfende Wort
	reg  [7:0]  beat_q;       // Wörter im laufenden Schreib-Burst
	reg  [31:0] seed_q;
	reg  [8:0]  rd_out_q;     // angeforderte, noch nicht gelieferte Lesewörter
	reg         start_pend_q; // Start gemerkt, bis der Port frei ist

	assign ddram_be = 8'hFF;

	// Der Reset löscht ddram_we/ddram_rd nicht hart (siehe unten). In der
	// Hardware starten alle Register nach dem Laden mit 0; dem Simulator
	// muss man das sagen. Kein Startwert im RTL (Quartus-Pro-Falle 16754).
	// synthesis translate_off
	initial begin
		ddram_we = 1'b0;
		ddram_rd = 1'b0;
		beat_q   = 8'd0;
		rd_out_q = 9'd0;
	end
	// synthesis translate_on

	function [63:0] pattern(input [31:0] i, input [31:0] seed);
		pattern = {i ^ 32'hA5A5_5A5A, i ^ seed};
	endfunction

	always @(posedge clk) begin
		// Offene Lesewörter zählen (auch über einen Reset hinweg)
		rd_out_q <= rd_out_q + ((ddram_rd && !ddram_busy) ? BURST9 : 9'd0)
		                     - (ddram_dout_ready ? 9'd1 : 9'd0);

		// Einen angefangenen Avalon-Befehl nie abbrechen: Ein halber
		// Schreib-Burst lässt die F2SDRAM-Seite ewig auf den Rest warten (die
		// SMMU des HPS hängt dann, Linux mit ihr); ein wartender Befehl muss
		// anliegen, bis er angenommen ist. Nach einem Reset (und in S_IDLE)
		// daher: Burst mit beliebigen Daten zu Ende schreiben, Lesebefehl
		// stehen lassen, bis busy = 0.
		if (rst || state_q == S_IDLE) begin
			if (ddram_we && !ddram_busy) begin
				if (beat_q == 8'd0) ddram_we <= 1'b0;   // letztes Wort übernommen
				else beat_q <= (beat_q == BURST - 1) ? 8'd0 : beat_q + 1'd1;
			end
			if (ddram_rd && !ddram_busy) ddram_rd <= 1'b0;
		end

		if (rst) begin
			state_q      <= S_IDLE;
			start_pend_q <= 1'b0;
			running_q    <= 1'b0;
			done_q       <= 1'b0;
			pass_q       <= 1'b0;
			err_q        <= 16'd0;
			seed_q       <= 32'h0000_0001;
		end else begin
			if (start) start_pend_q <= 1'b1;

			case (state_q)
			// Start erst, wenn der Port frei ist und keine Lesedaten eines
			// abgebrochenen Laufs mehr unterwegs sind
			S_IDLE: if ((start || start_pend_q) && !ddram_we && !ddram_rd && rd_out_q == 9'd0) begin
				start_pend_q <= 1'b0;
				running_q   <= 1'b1;
				done_q      <= 1'b0;
				pass_q      <= 1'b0;
				err_q       <= 16'd0;
				wr_cycles_q <= 32'd0;
				rd_cycles_q <= 32'd0;
				idx_q       <= 0;
				chk_q       <= 0;
				beat_q      <= 8'd0;
				state_q     <= S_WR;
			end

			// Schreiben: ein Wort pro Takt, solange busy = 0. Adresse und
			// burstcnt gelten mit dem ersten Wort eines Bursts.
			S_WR: begin
				wr_cycles_q <= wr_cycles_q + 1'd1;
				if (!ddram_we || !ddram_busy) begin
					if (idx_q == WORDS) begin
						ddram_we <= 1'b0;
						idx_q    <= 0;
						state_q  <= S_RD_CMD;
					end else begin
						ddram_we  <= 1'b1;
						ddram_din <= pattern(idx_q, seed_q);
						if (beat_q == 8'd0) begin
							ddram_addr     <= BASE + idx_q;
							ddram_burstcnt <= BURST[7:0];
						end
						beat_q <= (beat_q == BURST - 1) ? 8'd0 : beat_q + 1'd1;
						idx_q  <= idx_q + 1'd1;
					end
				end
			end

			// Lesen: Befehl so lange anlegen, bis busy = 0 ...
			S_RD_CMD: begin
				rd_cycles_q <= rd_cycles_q + 1'd1;
				if (!ddram_rd) begin
					ddram_rd       <= 1'b1;
					ddram_addr     <= BASE + idx_q;
					ddram_burstcnt <= BURST[7:0];
				end else if (!ddram_busy) begin
					ddram_rd <= 1'b0;
					idx_q    <= idx_q + BURST;
					state_q  <= S_RD_DATA;
				end
			end

			// ... dann die Daten des Bursts abwarten (dout_ready je Wort).
			S_RD_DATA: begin
				rd_cycles_q <= rd_cycles_q + 1'd1;
				if (chk_q == idx_q)
					state_q <= (idx_q == WORDS) ? S_DONE : S_RD_CMD;
			end

			S_DONE: begin
				running_q <= 1'b0;
				done_q    <= 1'b1;
				pass_q    <= (err_q == 16'd0);
				seed_q    <= {seed_q[30:0], seed_q[31] ^ seed_q[21] ^ seed_q[1] ^ seed_q[0]};
				state_q   <= S_IDLE;
			end

			default: state_q <= S_IDLE;
			endcase

			// Vergleich läuft neben der Zustandsmaschine her: Lesedaten
			// kommen auch noch, während der nächste Befehl angelegt wird.
			if (ddram_dout_ready && running_q) begin
				if (ddram_dout != pattern(chk_q, seed_q) && err_q != 16'hFFFF)
					err_q <= err_q + 1'd1;
				chk_q <= chk_q + 1'd1;
			end
		end
	end

endmodule

`default_nettype wire
