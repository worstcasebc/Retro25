// SPDX-License-Identifier: GPL-3.0-or-later
// tester486 — prüft den SDRAM-Controller des z486 (upstream sdram.v) auf dem
// Onboard-SDRAM des DE25 (P5 Z3). Ersetzt MiSTers "tester" im Memtest-Rahmen
// (gleiche Schnittstelle: Pass-/Fehlerzähler, SDRAM-Pins).
//
// Takt: clk (Controller- und SDRAM-Takt, Ziel 85 MHz wie z486 "production").
// Reset: rst_n (aktiv low, wie MiSTers tester).
// Ablauf je Durchlauf über den ganzen Speicher (128 MB, beide Chips):
//   1. jedes Dword voll schreiben (Muster aus Adresse und Durchlauf)
//   2. je Dword ein Byte über DQM überschreiben (Byte = invertiertes Muster)
//   3. alles lesen und vergleichen — gerade Durchläufe als "Line Reads"
//      (4 Dwords mit Wrap ab wechselndem Start-Dword, wie der CPU-Cache),
//      ungerade als lineare Bursts zu 8 Dwords
// failcount zählt falsche Dwords, fehlende/überzählige Antworten und
// Zeitüberschreitungen (Wächter: 4096 Takte ohne Fortschritt); passcount
// zählt fertige Durchläufe.
// SIM=1 verteilt einen kleinen Adressbereich (2^14 Dwords) auf beide Chips,
// alle Bänke und vier Zeilen — für die Testbench mit sdram_chip_model.

module tester486 #(
	parameter FREQ = 85_000_000,
	parameter SIM  = 0
) (
	input             clk,
	input             rst_n,

	input       [1:0] sz,           // ungenutzt (immer 128 MB), wie tester
	input       [1:0] chip,         // ungenutzt

	output reg [31:0] passcount,
	output reg [31:0] failcount,

	inout      [15:0] DRAM_DQ,
	output     [12:0] DRAM_ADDR,
	output            DRAM_LDQM, DRAM_UDQM,
	output            DRAM_WE_N,
	output            DRAM_CAS_N,
	output            DRAM_RAS_N,
	output            DRAM_CS_N,
	output            DRAM_BA_0,
	output            DRAM_BA_1
);

localparam IW = SIM ? 14 : 25;          // Bits des Dword-Index
localparam [IW-1:0] I_LAST = {IW{1'b1}};

// Dword-Index -> Byte-Adresse. SIM: {Chip, Bank, Zeile[1:0], Spalte[8:0]}.
function [26:0] map_addr(input [IW-1:0] i);
	if (SIM) map_addr = {i[13], i[12:11], 11'd0, i[10:9], i[8:0], 2'b00};
	else     map_addr = {i, 2'b00};
endfunction

// Muster: je Adresse eindeutig, Hälften verschieden, je Durchlauf anders
reg  [31:0] seed;
function [31:0] pat(input [IW-1:0] i);
	reg [24:0] x;
	begin
		x = i;
		pat = {~x[24:16], x[6:0], x[15:0]} ^ seed;
	end
endfunction

function [1:0] lane(input [IW-1:0] i);
	lane = i[1:0] ^ passcount[1:0];
endfunction

// Erwarteter Inhalt nach Schritt 2
function [31:0] expect_val(input [IW-1:0] i);
	expect_val = pat(i) ^ (32'h000000FF << {lane(i), 3'b000});
endfunction

// ---------------------------------------------------------------- Controller
wire        ready0, resp_valid0, burst_done0, busy;
wire [31:0] dout0;
reg         valid0, wr0;
reg  [26:0] addr0;
reg  [31:0] din0;
reg   [3:0] be0, burst_cnt0;
reg         burst_wrap0;
wire  [1:0] dqm, ba;

sdram #(
	.FREQ(FREQ),
	.HAS_DQM(1'b1),
	.FAST_GRADE(1'b1)
) ctrl (
	.SDRAM_DQ(DRAM_DQ),
	.SDRAM_A(DRAM_ADDR),
	.SDRAM_DQM(dqm),
	.SDRAM_BA(ba),
	.SDRAM_nWE(DRAM_WE_N),
	.SDRAM_nRAS(DRAM_RAS_N),
	.SDRAM_nCAS(DRAM_CAS_N),
	.SDRAM_nCS(DRAM_CS_N),
	.SDRAM_CKE(),
	.clk(clk),
	.resetn(rst_n),
	.nce(1'b0),
	.refresh_allowed(1'b1),
	.busy(busy),
	.sdram_size(2'd3),
	.valid0(valid0), .ready0(ready0), .wr0(wr0), .addr0(addr0), .din0(din0), .dout0(dout0),
	.be0(be0), .resp_valid0(resp_valid0), .burst_cnt0(burst_cnt0), .burst_wrap0(burst_wrap0),
	.burst_done0(burst_done0),
	.valid1(1'b0), .ready1(), .wr1(1'b0), .addr1(27'd0), .din1(32'd0), .dout1(), .be1(4'd0),
	.resp_valid1(), .burst_cnt1(4'd0), .burst_wrap1(1'b0), .burst_done1(),
	.valid2(1'b0), .ready2(), .wr2(1'b0), .addr2(27'd0), .din2(32'd0), .dout2(), .be2(4'd0),
	.resp_valid2(), .burst_cnt2(4'd0), .burst_wrap2(1'b0), .burst_done2()
);

assign {DRAM_UDQM, DRAM_LDQM} = dqm;
assign {DRAM_BA_1, DRAM_BA_0} = ba;

// ---------------------------------------------------------------- Ablauf
localparam S_WAIT = 3'd0, S_WRITE = 3'd1, S_BYTE = 3'd2, S_RREQ = 3'd3, S_RDATA = 3'd4;

reg  [2:0] state;
reg [IW-1:0] i;          // aktueller Dword-Index (Schreiben) bzw. Blockanfang (Lesen)
reg  [3:0] k;            // Antworten im laufenden Burst
reg  [3:0] nwords;       // Dwords je Lese-Burst
reg  [1:0] start;        // Start-Dword im Line Read
reg [11:0] watchdog;

wire       line_mode = ~passcount[0];
wire [IW-1:0] rd_index = line_mode ? {i[IW-1:2], start + k[1:0]} : i + k;
wire [IW-1:0] i_next   = i + nwords;        // 0 = Durchlauf fertig (Überlauf)

// Fehler dieses Takts (mehrere möglich): falsches Dword, falsche Anzahl
wire bad_word  = (state == S_RDATA) && resp_valid0 && (dout0 != expect_val(rd_index));
wire bad_count = (state == S_RDATA) && burst_done0 && ((k + resp_valid0) != nwords);
wire timeout   = (state != S_WAIT) && &watchdog;

always @(posedge clk) begin
	if (!rst_n) begin
		state     <= S_WAIT;
		valid0    <= 1'b0;
		passcount <= 32'd0;
		failcount <= 32'd0;
		seed      <= 32'h5A3C_96E1;
		watchdog  <= 12'd0;
	end else begin
		watchdog <= watchdog + 1'd1;
		if (ready0 || resp_valid0) watchdog <= 12'd0;

		case (state)
		S_WAIT: if (!busy) begin                   // Controller initialisiert
			i      <= {IW{1'b0}};
			state  <= S_WRITE;
		end

		S_WRITE: begin
			valid0 <= 1'b1;
			wr0    <= 1'b1;
			addr0  <= map_addr(i);
			din0   <= pat(i);
			be0    <= 4'b1111;
			if (valid0 && ready0) begin
				valid0 <= 1'b0;
				if (i == I_LAST) state <= S_BYTE;
				i <= i + 1'd1;
			end
		end

		S_BYTE: begin
			valid0 <= 1'b1;
			wr0    <= 1'b1;
			addr0  <= map_addr(i);
			din0   <= ~pat(i);
			be0    <= 4'b0001 << lane(i);
			if (valid0 && ready0) begin
				valid0 <= 1'b0;
				if (i == I_LAST) state <= S_RREQ;
				i <= i + 1'd1;
			end
		end

		S_RREQ: begin
			// Line Read: Block = 4 Dwords, Start wechselt; sonst 8 Dwords linear
			nwords      <= line_mode ? 4'd4 : 4'd8;
			start       <= i[3:2] + passcount[2:1];
			valid0      <= 1'b1;
			wr0         <= 1'b0;
			be0         <= 4'b1111;
			burst_cnt0  <= line_mode ? 4'd4 : 4'd8;
			burst_wrap0 <= line_mode;
			addr0       <= map_addr(line_mode ? {i[IW-1:2], i[3:2] + passcount[2:1]} : i);
			k           <= 4'd0;
			if (valid0 && ready0) begin
				valid0 <= 1'b0;
				state  <= S_RDATA;
			end
		end

		S_RDATA: begin
			if (resp_valid0) k <= k + 1'd1;
			if (burst_done0) begin
				i <= i_next;
				if (i_next == {IW{1'b0}}) begin   // ganzer Speicher gelesen
					passcount <= passcount + 1'd1;
					seed      <= {seed[30:0], seed[31] ^ seed[21] ^ seed[1] ^ seed[0]};
					state     <= S_WRITE;
				end else
					state <= S_RREQ;
			end
		end

		default: state <= S_WAIT;
		endcase

		failcount <= failcount + bad_word + bad_count + timeout;

		// Wächter: kein ready/Antwort seit 4096 Takten -> neu anfangen
		if (timeout) begin
			valid0 <= 1'b0;
			state  <= S_WAIT;
		end
	end
end

endmodule
