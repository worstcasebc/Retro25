// SPDX-License-Identifier: GPL-3.0-or-later
// f2s_halt_de25 — DDR-Port vor dem Umladen des FPGA sauber anhalten.
//
// Zweck:  Wird das FPGA neu geladen, während über F2SDRAM ein Burst läuft
//         oder Lesedaten unterwegs sind, wartet die HPS-Seite ewig auf den
//         Rest. Auf dem Agilex 5 hängt dann die SMMU (CMD_SYNC timeout) und
//         mit ihr Linux. Dieses Modul sitzt zwischen einem Avalon-Master
//         (ascal, Core, ddr_svc) und dem Port zu qsys_top:
//          - halt = 1: Der Master wird zwischen zwei Befehlen angehalten
//            (waitrequest = 1); ein angefangener Schreib-Burst darf zu Ende
//            laufen, ein wartender Befehl bleibt stehen, bis er angenommen ist.
//          - takeover = 1 (nur TAKEOVER = 1, für Master, die der Core-Reset
//            mitten im Burst abwürgt): wie halt, aber den angefangenen
//            Schreib-Burst bzw. wartenden Befehl stellt das Modul selbst fertig
//            (Schreib-Beats mit byteenable = 0, ändern also nichts).
//            Wie MiSTers f2sdram_safe_terminator, der beim Core-Reset greift.
//          - idle = 1: angehalten, kein Befehl offen, alle Lesedaten zurück
//            und danach QUIET Takte Ruhe (für Schreibantworten hinter der
//            Clock Crossing Bridge). Dann darf Linux das FPGA umladen.
// Takt:   clk = Takt des Ports; halt/takeover/rst schon in clk synchronisiert.
// Hinweis: Lesedaten werden immer durchgereicht (auch angehalten).
// Analogie: Eine Schranke vor der Brücke: Wer schon drauf ist, fährt zu Ende,
//         neue Autos warten; erst wenn die Brücke leer ist, kommt das Signal.

`default_nettype none

module f2s_halt_de25 #(
	parameter DW       = 64,
	parameter TAKEOVER = 0,
	parameter QUIET    = 1024
) (
	input  wire          clk,
	input  wire          rst,
	input  wire          halt,
	input  wire          takeover,
	output wire          idle,

	// vom Master
	input  wire   [31:0] s_address,
	input  wire    [7:0] s_burstcount,
	input  wire          s_read,
	input  wire          s_write,
	input  wire [DW-1:0] s_writedata,
	input  wire [DW/8-1:0] s_byteenable,
	output wire          s_waitrequest,
	output wire [DW-1:0] s_readdata,
	output wire          s_readdatavalid,

	// zum Port
	output wire   [31:0] m_address,
	output wire    [7:0] m_burstcount,
	output wire          m_read,
	output wire          m_write,
	output wire [DW-1:0] m_writedata,
	output wire [DW/8-1:0] m_byteenable,
	input  wire          m_waitrequest,
	input  wire [DW-1:0] m_readdata,
	input  wire          m_readdatavalid
);

	localparam [15:0] QN = QUIET;

	wire take = (TAKEOVER != 0) && takeover;
	wire stop = halt | take;

	reg        blk_q;          // 1 = Master abgehängt
	reg        held_q;         // Ersatzbefehl offen (nur im Takeover)
	reg        held_rd_q;
	reg [31:0] held_addr_q;
	reg  [7:0] held_bc_q;
	reg  [7:0] wr_left_q;      // noch offene Beats des laufenden Schreib-Bursts
	reg [15:0] rd_out_q;       // noch offene Lese-Beats
	reg [15:0] quiet_q;

	// Ersatzbefehle im Takeover: erst der wartende Befehl, dann die
	// restlichen Beats des Schreib-Bursts
	wire rep_rd = blk_q & held_q & held_rd_q;
	wire rep_wr = blk_q & ((held_q & ~held_rd_q) | (~held_q & (wr_left_q != 8'd0)));

	assign m_address     = blk_q ? held_addr_q : s_address;
	assign m_burstcount  = blk_q ? held_bc_q   : s_burstcount;
	assign m_read        = blk_q ? rep_rd      : s_read;
	assign m_write       = blk_q ? rep_wr      : s_write;
	assign m_writedata   = s_writedata;
	assign m_byteenable  = blk_q ? {DW/8{1'b0}} : s_byteenable;
	assign s_waitrequest = blk_q | m_waitrequest;
	assign s_readdata      = m_readdata;
	assign s_readdatavalid = m_readdatavalid;

	wire acc_rd = m_read  & ~m_waitrequest;
	wire acc_wr = m_write & ~m_waitrequest;
	wire hold_now = (m_read | m_write) & m_waitrequest;   // muss im nächsten Takt bleiben

	// Beats des laufenden Schreib-Bursts nach diesem Takt
	wire [7:0] wr_left_next = !acc_wr          ? wr_left_q :
	                          (wr_left_q == 0) ? m_burstcount - 8'd1 :
	                                             wr_left_q - 8'd1;
	wire [15:0] rd_out_next = rd_out_q + (acc_rd ? {8'd0, m_burstcount} : 16'd0)
	                                   - (m_readdatavalid ? 16'd1 : 16'd0);

	wire clean = blk_q & ~held_q & (wr_left_q == 8'd0) & (rd_out_q == 16'd0);
	assign idle = clean & (quiet_q == QN);

	always @(posedge clk) begin
		if (rst) begin
			blk_q     <= 1'b1;
			held_q    <= 1'b0;
			wr_left_q <= 8'd0;
			rd_out_q  <= 16'd0;
			quiet_q   <= 16'd0;
		end else begin
			wr_left_q <= wr_left_next;
			rd_out_q  <= rd_out_next;

			if (!blk_q) begin
				// Durchreichen; anhalten erst an einer Befehlsgrenze, im
				// Takeover sofort (Rest übernimmt das Modul)
				if (take && (hold_now || wr_left_next != 8'd0)) begin
					blk_q       <= 1'b1;
					held_q      <= hold_now & (wr_left_q == 8'd0);  // neuer Befehl wartet
					held_rd_q   <= m_read;
					held_addr_q <= m_address;
					held_bc_q   <= m_burstcount;
				end else if (stop && !hold_now && wr_left_next == 8'd0)
					blk_q <= 1'b1;
			end else begin
				if (held_q && !m_waitrequest) held_q <= 1'b0;
				if (!stop && !held_q && wr_left_q == 8'd0) blk_q <= 1'b0;
			end

			if (!clean || !stop) quiet_q <= 16'd0;
			else if (quiet_q != QN) quiet_q <= quiet_q + 16'd1;
		end
	end

endmodule

`default_nettype wire
