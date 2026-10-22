// SPDX-License-Identifier: GPL-3.0-or-later
// sdram_chip_model — Verhaltensmodell eines SDR-SDRAM-Chips (x16) für
// Testbenches (P5 Z3: z486-SDRAM-Controller mit zwei Chips).
//
// Takt: clk (Befehle werden an der steigenden Flanke übernommen, wie im Chip).
// Schnittstelle: die SDRAM-Pins eines Chips (cs_n, ras_n, cas_n, we_n, ba, a,
// dqm, dq). Versteht MRS (CAS-Latenz, nur Burst-Länge 1), ACT, READ/WRITE
// (A10 = Auto-Precharge), PRECHARGE (A10 = alle Bänke), AUTO REFRESH, DQM beim
// Schreiben. Lesedaten liegen ab kurz nach der (CL-1)-ten Flanke nach dem
// READ bis kurz nach der CL-ten an (wie tAC/tOH im Datenblatt).
// Prüft und meldet mit "FAIL" (zählt in errors): Befehl vor MRS, ACT auf
// offene Bank, READ/WRITE auf geschlossene Bank, tRCD, tRP (auch nach
// Auto-Precharge inkl. tWR), tRC, tRAS, tRFC, REFRESH bei offener Bank,
// Burst-Länge ungleich 1, Zeile außerhalb des abgebildeten Bereichs.
// Speicher: nur ROWB Zeilenbits je Bank werden abgebildet (klein halten);
// die Testbench muss in diesem Bereich bleiben (wird geprüft).
// Analogie: ein Prüfer mit Stoppuhr, der jeden Befehl gegen das Datenblatt hält.

`timescale 1ns/1ps

module sdram_chip_model #(
	parameter NAME  = "chip",
	parameter ROWB  = 4,       // abgebildete Zeilenbits je Bank
	parameter T_RCD = 2,       // Mindestabstände in Takten
	parameter T_RP  = 2,
	parameter T_RC  = 6,
	parameter T_RAS = 4,
	parameter T_WR  = 1,
	parameter T_RFC = 6,
	parameter BAD_BIT = -1     // >= 0: dieses Datenbit beim Lesen kippen (Gegenprobe)
) (
	input             clk,
	input             cke,
	input             cs_n,
	input             ras_n,
	input             cas_n,
	input             we_n,
	input       [1:0] ba,
	input      [12:0] a,
	input       [1:0] dqm,
	inout      [15:0] dq
);

localparam MEMW = 2 + ROWB + 10;

reg [15:0] mem [0:(1<<MEMW)-1];

integer errors = 0;
integer acts = 0;              // Anzahl ACT (zeigt, dass der Chip benutzt wird)
integer cyc = 0;
reg     mrs_done = 0;
integer cl = 2;

reg        open_ [0:3];
reg [12:0] row_  [0:3];
integer    t_act [0:3];        // Takt des letzten ACT
integer    t_pre [0:3];        // Takt, ab dem der Precharge läuft
integer    t_ref;              // Takt des letzten REFRESH

// Lesepipeline: Daten und Gültigkeit je Latenzstufe
reg [15:0] rd_data [0:7];
reg  [7:0] rd_valid;

reg [15:0] dq_drv;
reg        dq_oe = 0;
assign dq = dq_oe ? dq_drv : 16'hzzzz;

integer i;
initial begin
	for (i = 0; i < 4; i = i + 1) begin
		open_[i] = 0; row_[i] = 0; t_act[i] = -1000; t_pre[i] = -1000;
	end
	t_ref = -1000;
	rd_valid = 0;
	for (i = 0; i < (1<<MEMW); i = i + 1) mem[i] = 16'hxxxx;
end

task fail(input [8*64-1:0] what);
	begin
		errors = errors + 1;
		$display("FAIL: %0s Takt %0d: %0s", NAME, cyc, what);
	end
endtask

function [MEMW-1:0] idx(input [1:0] b, input [12:0] r, input [9:0] c);
	idx = {b, r[ROWB-1:0], c};
endfunction

wire [2:0] cmd = {ras_n, cas_n, we_n};
localparam CMD_MRS = 3'b000, CMD_REF = 3'b001, CMD_PRE = 3'b010, CMD_ACT = 3'b011,
           CMD_WR  = 3'b100, CMD_RD  = 3'b101, CMD_NOP = 3'b111;

integer bnk;
reg [15:0] wdata;

always @(posedge clk) begin
	cyc = cyc + 1;

	// Lesedaten: Stufe 0 wird kurz nach dieser Flanke ausgegeben und bleibt
	// bis kurz nach der nächsten (Eingänge werden davor, an der Flanke selbst,
	// gelesen — die Ausgabe ist mit #0.5 verzögert wie tAC/tOH)
	rd_valid = rd_valid >> 1;
	for (i = 0; i < 7; i = i + 1) rd_data[i] = rd_data[i+1];
	dq_oe  <= #0.5 rd_valid[0];
	dq_drv <= #0.5 rd_data[0];

	if (cke && !cs_n && cmd != CMD_NOP) begin
		if (!mrs_done && cmd != CMD_MRS && cmd != CMD_PRE && cmd != CMD_REF)
			fail("Befehl vor MRS");
		bnk = ba;
		case (cmd)
		CMD_MRS: begin
			cl = a[6:4];
			if (a[2:0] != 3'b000) fail("Burst-Laenge != 1");
			if (cl != 2 && cl != 3) fail("CAS-Latenz nicht 2/3");
			mrs_done = 1;
		end
		CMD_ACT: begin
			if (open_[bnk]) fail("ACT auf offene Bank");
			if (cyc - t_pre[bnk] < T_RP) fail("tRP verletzt (ACT)");
			if (cyc - t_act[bnk] < T_RC) fail("tRC verletzt (ACT)");
			if (cyc - t_ref < T_RFC) fail("tRFC verletzt (ACT)");
			if (a >= (1 << ROWB)) fail("Zeile ausserhalb des Modells");
			open_[bnk] = 1; row_[bnk] = a; t_act[bnk] = cyc;
			acts = acts + 1;
		end
		CMD_RD, CMD_WR: begin
			if (!open_[bnk]) fail("READ/WRITE auf geschlossene Bank");
			if (cyc - t_act[bnk] < T_RCD) fail("tRCD verletzt");
			if (cmd == CMD_RD) begin
				rd_data[cl-1] = mem[idx(ba, row_[bnk], a[9:0])];
				if (BAD_BIT >= 0) rd_data[cl-1][BAD_BIT] = ~rd_data[cl-1][BAD_BIT];
				rd_valid[cl-1] = 1'b1;
			end else begin
				wdata = mem[idx(ba, row_[bnk], a[9:0])];
				if (!dqm[0]) wdata[7:0]  = dq[7:0];
				if (!dqm[1]) wdata[15:8] = dq[15:8];
				mem[idx(ba, row_[bnk], a[9:0])] = wdata;
			end
			if (a[10]) begin                     // Auto-Precharge
				// Precharge beginnt nach dem (einzigen) Datenwort bzw. nach tWR
				t_pre[bnk] = (cmd == CMD_WR) ? cyc + T_WR : cyc + 1;
				if (t_pre[bnk] - t_act[bnk] < T_RAS) fail("tRAS verletzt (Auto-Precharge)");
				open_[bnk] = 0;
			end
		end
		CMD_PRE: begin
			for (i = 0; i < 4; i = i + 1)
				if (a[10] || i == bnk) begin
					if (open_[i] && cyc - t_act[i] < T_RAS) fail("tRAS verletzt (PRECHARGE)");
					if (open_[i]) t_pre[i] = cyc;
					open_[i] = 0;
				end
		end
		CMD_REF: begin
			for (i = 0; i < 4; i = i + 1) begin
				if (open_[i]) fail("REFRESH bei offener Bank");
				if (cyc - t_pre[i] < T_RP) fail("tRP verletzt (REFRESH)");
			end
			if (cyc - t_ref < T_RFC) fail("tRFC verletzt (REFRESH)");
			t_ref = cyc;
		end
		default: fail("unbekannter Befehl");
		endcase
	end
end

endmodule
