// SPDX-License-Identifier: GPL-3.0-or-later
// pll_cfg_de25 — HDMI-PLL zur Laufzeit umstellen (Agilex-5-HVIO-IOPLL).
//
// Zweck:  Ersetzt MiSTers pll_cfg (altera_pll_reconfig, Cyclone V). sys_top
//         schreibt wie im Original Register im Cyclone-V-Format:
//           3 N-Zähler, 4 M-Zähler, 5 C-Zähler (nur C0), 2 Start;
//           Format: [15:8] high, [7:0] low, [16] bypass, [17] ungerade.
//           0, 7 (K, fraktional), 8, 9 werden angenommen und ignoriert —
//           die Agilex-5-IOPLL kann nur ganzzahlig.
//         Start übersetzt das in die Sequenz des Agilex-5-Handbuchs (813671,
//         Kap. 6.2.2) über den Port core_avl_* der IOPLL:
//           0x10[0]=1 Register freigeben, 0x58[7,21]=0 Kalibrierstatus
//           löschen, 0x40 M/N, 0x44 Ladungspumpe (Tabelle nach M), 0x5C C0,
//           0x80[2] Reset-Puls, 0x48[14]=1 Kalibrierung erlauben,
//           0x88[11]=1 Kalibrierung anfordern, auf locked warten,
//           0x88[11]=0 (abschaltbar), 0x48[14]=0.
//         Gemerkter Stand statt Lesen-Ändern-Schreiben: Nach dem Reset, wenn
//         die PLL eingerastet ist, und INIT_DELAY Takten liest der Baustein die
//         acht Register einmal ein, jedes doppelt, bis zwei gleiche Werte kommen
//         (0xFFFFFFFF gilt nie: so antwortet der Port am Board kurz nach dem
//         Laden, solange er nicht bereit ist — dann INIT_DELAY warten, neu). Danach schreibt er nur
//         noch aus diesem Stand (fremde Bits erhalten, eigene Bits geändert)
//         und liest nur zum Prüfen: 0x40, 0x44, 0x5C zurücklesen, ganzes Wort
//         vergleichen; weicht etwas ab, nach RETRY_PAUSE Takten die Sequenz
//         wiederholen (höchstens MAX_TRIES Versuche; mit 1 ms Pause überbrücken
//         8 Versuche gut 8 ms, länger als eine Umstellung der anderen PLL). Grund: Stellt ein Core gleichzeitig seine eigene
//         HVIO-PLL um (Memtest), gingen am Board Schreibzugriffe verloren und
//         Lesezugriffe lieferten falsche Werte — das Lesen-Ändern-Schreiben
//         brannte die falschen Werte in 0x44 ein, die PLL rastete nicht mehr
//         ein. Ursache der Störung im Baustein: ungeklärt (Handbuch schweigt).
//         Mehrere Exemplare (sys + Core): INIT_DELAY verschieden wählen, damit
//         sich schon das Einlesen nicht stört.
// Port:   Starres Byte-Protokoll: 4 Bytes je Register, LSB zuerst; Schreiben
//         10 Takte (5 x 0x00, b0 b1 b2 b3 b3), Lesen 10 Takte (b0 im 7. Takt),
//         danach Leertakte. Die gelesenen Bytes jedes Zugriffs werden
//         aufgezeichnet (cap), damit sich das Timing auf dem Board prüfen
//         lässt; ctrl stellt Adressform, Schreibform und Leseversatz um.
// Debug:  dbg_* (gleicher Takt, Lesedaten einen Takt später), Wortadressen:
//           0 Status  RO  [31:16] 0x504C ("PL"), [0] busy, [1] locked,
//                         [2] Timeout beim letzten Lauf, [3] Prüffehler beim
//                         letzten Lauf (auch nach 3 Versuchen falsch),
//                         [7:4] Zustand grob
//           1 ctrl    RW  [0] ES-Adressen (Byte-Offset), [1] Schreibform
//                         00 b0 b1 b2 b3, [3:2] Leseversatz +0..3,
//                         [4] 0x88[11] nach Lock NICHT zurücksetzen
//           2 raw_addr RW Byte-Offset [8:0]
//           3 raw_data W: Rohschreiben nach raw_addr; R: letztes Lesewort
//           4 W: Rohlesen von raw_addr starten
//           5..7 cap  RO  Bytes 0..11 des letzten Lesezugriffs (13: 12..13)
//           8 M, 9 N, 10 C  RW  Schattenregister (Cyclone-V-Format)
//          11 Zähler  RO  [7:0] Starts, [15:8] fertig, [23:16] Timeouts,
//                         [31:24] Wiederholungen nach Prüffehler
//         Rohschreiben auf eines der acht Register ändert auch den gemerkten
//         Stand (Werkzeuge wie p3/linux/pll_cfg.py wr).
//          12 W: Sequenz mit den Schattenregistern starten (ohne Main)
// Takt:   clk (50 MHz, auch core_avl_clk); locked asynchron (2 FF).
// Analogie: Ein Dolmetscher: Main spricht weiter "Cyclone V", die PLL
//         versteht nur "Agilex 5" — und nur langsam, Byte für Byte.

`default_nettype none

module pll_cfg_de25 #(
	parameter LOCK_WAIT_MIN = 16'd5000,      // Takte vor dem Prüfen von locked
	parameter LOCK_TIMEOUT  = 24'd5_000_000, // 100 ms bei 50 MHz
	parameter INIT_DELAY    = 24'd50_000,    // Takte mit Lock vor dem Einlesen (1 ms)
	parameter MAX_TRIES     = 4'd8,          // Versuche je Umstellung (Prüfen)
	parameter RETRY_PAUSE   = 24'd50_000     // Pause vor einer Wiederholung (1 ms)
) (
	input  wire        clk,
	input  wire        rst,

	// wie altera_pll_reconfig (mgmt_*)
	input  wire        mgmt_write,
	input  wire  [5:0] mgmt_address,
	input  wire [31:0] mgmt_writedata,
	output wire        mgmt_waitrequest,

	// Debug-Zugriff
	input  wire  [3:0] dbg_address,
	input  wire        dbg_write,
	input  wire [31:0] dbg_writedata,
	input  wire        dbg_read,
	output reg  [31:0] dbg_readdata,

	// zur IOPLL
	output reg   [8:0] core_avl_address,
	output reg         core_avl_read,
	output reg         core_avl_write,
	output reg   [7:0] core_avl_writedata,
	input  wire  [7:0] core_avl_readdata,
	input  wire        pll_locked
);

	// --- Schattenregister und Steuerung --------------------------------------
	reg [17:0] m_q, n_q, c_q;
	reg  [4:0] ctrl_q;
	reg  [8:0] raw_addr_q;
	reg [31:0] raw_wdata_q;
	reg [31:0] rd_word_q;
	reg [111:0] cap_q;
	reg  [7:0] cnt_start_q, cnt_done_q, cnt_tmo_q, cnt_retry_q;
	reg        tmo_q, vfail_q;
	reg  [3:0] retry_q;

	// Gemerkter Stand der acht Register (Index siehe reg_addr)
	reg [31:0] hw_q [0:7];
	function [8:0] reg_addr(input [2:0] k);
		case (k)
			3'd0: reg_addr = 9'h010;  3'd1: reg_addr = 9'h058;
			3'd2: reg_addr = 9'h040;  3'd3: reg_addr = 9'h044;
			3'd4: reg_addr = 9'h05C;  3'd5: reg_addr = 9'h080;
			3'd6: reg_addr = 9'h048;  default: reg_addr = 9'h088;
		endcase
	endfunction
	// Index eines Registers, 4'hF = keines der acht
	function [3:0] reg_idx(input [8:0] a);
		case (a)
			9'h010: reg_idx = 4'd0;  9'h058: reg_idx = 4'd1;
			9'h040: reg_idx = 4'd2;  9'h044: reg_idx = 4'd3;
			9'h05C: reg_idx = 4'd4;  9'h080: reg_idx = 4'd5;
			9'h048: reg_idx = 4'd6;  9'h088: reg_idx = 4'd7;
			default: reg_idx = 4'hF;
		endcase
	endfunction

	wire locked_s;
	sync_2ff lock_sync(.clk(clk), .d_async(pll_locked), .d_sync_q(locked_s));

	// Zählerwert = high + low, bypass = 1
	function [8:0] total(input [17:0] v);
		total = v[16] ? 9'd1 : ({1'b0, v[15:8]} + {1'b0, v[7:0]});
	endfunction

	// Ladungspumpe [15:1] nach M (Handbuch Tabelle 23)
	function [14:0] cp_for_m(input [8:0] m);
		if      (m <= 2)   cp_for_m = 15'b00011_10101_11111;
		else if (m <= 7)   cp_for_m = 15'b00011_10001_11010;
		else if (m <= 10)  cp_for_m = 15'b00010_10000_11000;
		else if (m <= 15)  cp_for_m = 15'b00010_01100_10010;
		else if (m <= 23)  cp_for_m = 15'b00001_01001_01110;
		else if (m <= 43)  cp_for_m = 15'b00000_01000_01100;
		else if (m <= 64)  cp_for_m = 15'b00000_00110_01001;
		else if (m <= 85)  cp_for_m = 15'b00000_00110_00110;
		else if (m <= 124) cp_for_m = 15'b00000_00101_00101;
		else if (m <= 160) cp_for_m = 15'b00000_00011_00011;
		else               cp_for_m = 15'b00000_00010_00010;
	endfunction

	wire [8:0] m_tot = total(m_q);

	// Register 0x40: M [28:20] total, [31] bypass; N [7:0] high, [16:9] low,
	// [17] ungerade, [8] bypass
	wire [31:0] mn_mask = 32'h9FF3_FFFF;
	wire [31:0] mn_val  = {m_q[16], 2'b00, m_tot, 2'b00, n_q[17], n_q[7:0], n_q[16], n_q[15:8]};
	// Register 0x5C (C0): [7:0] high, [30:23] low, [31] ungerade, [8] bypass
	wire [31:0] c_mask  = 32'hFF80_01FF;
	wire [31:0] c_val   = {c_q[17], c_q[7:0], 14'd0, c_q[16], c_q[15:8]};

	// --- Byte-Engine: ein 32-bit-Register lesen oder schreiben ---------------
	reg        eng_go, eng_wr;
	reg  [8:0] eng_addr;
	reg [31:0] eng_wdata;
	reg        eng_busy;
	reg  [4:0] eng_cyc;
	reg [31:0] eng_rdata;

	wire [1:0] rd_skew = ctrl_q[3:2];
	wire [3:0] rd_first = 4'd6 + rd_skew;   // Index von b0 in cap

	always @(posedge clk) begin
		if (rst) begin
			eng_busy <= 1'b0;
			core_avl_read  <= 1'b0;
			core_avl_write <= 1'b0;
			core_avl_writedata <= 8'h00;
		end else if (eng_go & ~eng_busy) begin
			eng_busy <= 1'b1;
			eng_cyc  <= 5'd0;
			core_avl_address <= ctrl_q[0] ? eng_addr : {2'b00, eng_addr[8:2]};
			core_avl_write <= eng_wr;
			core_avl_read  <= ~eng_wr;
			core_avl_writedata <= 8'h00;
		end else if (eng_busy) begin
			eng_cyc <= eng_cyc + 1'd1;
			// Takt eng_cyc ist gerade auf dem Bus; Daten für eng_cyc+1 setzen
			if (core_avl_write) begin
				case (eng_cyc)
					5'd4: core_avl_writedata <= ctrl_q[1] ? 8'h00 : eng_wdata[7:0];
					5'd5: core_avl_writedata <= ctrl_q[1] ? eng_wdata[7:0]   : eng_wdata[15:8];
					5'd6: core_avl_writedata <= ctrl_q[1] ? eng_wdata[15:8]  : eng_wdata[23:16];
					5'd7: core_avl_writedata <= ctrl_q[1] ? eng_wdata[23:16] : eng_wdata[31:24];
					5'd8: core_avl_writedata <= eng_wdata[31:24];
					default: ;
				endcase
			end
			if (eng_cyc == 5'd9) begin
				core_avl_write <= 1'b0;
				core_avl_read  <= 1'b0;
				core_avl_writedata <= 8'h00;
			end
			// Lesedaten aufzeichnen: cap Byte i = Bus in Takt i
			if (~eng_wr && eng_cyc < 5'd14)
				cap_q[eng_cyc*8 +: 8] <= core_avl_readdata;
			// 10 Takte Zugriff + 4 Takte Nachlauf (cap) + Leertakte
			if (eng_cyc == 5'd21) eng_busy <= 1'b0;
		end
	end

	// Lesewort aus cap (nach Ende des Zugriffs gültig)
	always @(*) eng_rdata = cap_q[rd_first*8 +: 32];

	// --- Ablaufsteuerung -----------------------------------------------------
	localparam S_IDLE   = 5'd0,
	           S_RAW    = 5'd1,   // Rohzugriff läuft
	           S_INIT   = 5'd2,   // nach dem Reset: warten, dann einlesen
	           S_WR     = 5'd3,   // Schreiben läuft
	           S_STEP   = 5'd4,   // nächsten Schritt wählen
	           S_WAIT   = 5'd5,   // Wartezeit
	           S_LOCK   = 5'd6,   // auf locked warten
	           S_VERIFY = 5'd7,   // Prüfen: Lesen läuft
	           S_INIT_A = 5'd8,   // Einlesen: erstes Lesen läuft
	           S_INIT_B = 5'd9,   // Einlesen: zweites Lesen läuft
	           S_PAUSE  = 5'd10;  // Pause vor einer Wiederholung

	reg  [4:0] state;
	reg  [3:0] step;
	reg  [8:0] rmw_addr;
	reg [31:0] rmw_mask, rmw_val;
	reg [23:0] wait_cnt;
	reg        eng_busy_q;
	reg        start_q, start_pend_q;
	reg        wr_seen_q;
	reg  [2:0] init_k;
	reg [31:0] init_a;
	reg  [3:0] step_k;     // Registerindex des aktuellen Schritts

	wire eng_done = eng_busy_q & ~eng_busy;

	// Schritte der Sequenz: Adresse, Maske, Wert
	always @(*) begin
		rmw_addr = 9'h000; rmw_mask = 32'h0; rmw_val = 32'h0;
		case (step)
			4'd0:  begin rmw_addr = 9'h010; rmw_mask = 32'h0000_0001; rmw_val = 32'h0000_0001; end
			4'd1:  begin rmw_addr = 9'h058; rmw_mask = 32'h0020_0080; rmw_val = 32'h0; end
			4'd2:  begin rmw_addr = 9'h040; rmw_mask = mn_mask; rmw_val = mn_val; end
			4'd3:  begin rmw_addr = 9'h044; rmw_mask = 32'h0000_FFFE; rmw_val = {16'd0, cp_for_m(m_tot), 1'b0}; end
			4'd4:  begin rmw_addr = 9'h05C; rmw_mask = c_mask; rmw_val = c_val; end
			4'd5:  begin rmw_addr = 9'h080; rmw_mask = 32'h0000_0004; rmw_val = 32'h0000_0004; end
			4'd6:  begin rmw_addr = 9'h080; rmw_mask = 32'h0000_0004; rmw_val = 32'h0; end
			4'd7:  begin rmw_addr = 9'h048; rmw_mask = 32'h0000_4000; rmw_val = 32'h0000_4000; end
			4'd8:  begin rmw_addr = 9'h088; rmw_mask = 32'h0000_0800; rmw_val = 32'h0000_0800; end
			// 9: auf locked warten (kein Registerzugriff)
			4'd10: begin rmw_addr = 9'h088; rmw_mask = 32'h0000_0800; rmw_val = 32'h0; end
			4'd11: begin rmw_addr = 9'h048; rmw_mask = 32'h0000_4000; rmw_val = 32'h0; end
			// Prüfen (nur lesen, ganzes Wort mit dem gemerkten Stand vergleichen)
			4'd12: rmw_addr = 9'h040;
			4'd13: rmw_addr = 9'h044;
			4'd14: rmw_addr = 9'h05C;
			default: ;
		endcase
	end

	assign mgmt_waitrequest = start_q | start_pend_q | (state != S_IDLE) | wr_seen_q;

	always @(posedge clk) begin
		eng_busy_q <= eng_busy;
		eng_go     <= 1'b0;
		start_q    <= 1'b0;
		wr_seen_q  <= mgmt_write;

		if (rst) begin
			state <= S_INIT;
			wait_cnt <= 24'd0;
			init_k <= 3'd0;
			start_pend_q <= 1'b0;
			ctrl_q <= 5'd0;
			raw_addr_q <= 9'd0;
			// Startwerte wie pll_hdmi_de25 (148,5 MHz: N 5, M 297, C 20)
			m_q <= {2'b10, 8'd149, 8'd148};
			n_q <= {2'b10, 8'd3, 8'd2};
			c_q <= {2'b00, 8'd10, 8'd10};
			cnt_start_q <= 8'd0; cnt_done_q <= 8'd0; cnt_tmo_q <= 8'd0; cnt_retry_q <= 8'd0;
			tmo_q <= 1'b0;
			vfail_q <= 1'b0;
		end else begin
			// Register von sys_top (Cyclone-V-Format)
			if (start_q && state != S_IDLE) start_pend_q <= 1'b1;   // nach dem Einlesen nachholen
			if (mgmt_write) begin
				case (mgmt_address)
					6'd2: start_q <= 1'b1;
					6'd3: n_q <= mgmt_writedata[17:0];
					6'd4: m_q <= mgmt_writedata[17:0];
					6'd5: if (mgmt_writedata[22:18] == 5'd0) c_q <= mgmt_writedata[17:0];
					default: ;
				endcase
			end

			// Debug-Schreibzugriffe
			if (dbg_write) begin
				case (dbg_address)
					4'd1:  ctrl_q <= dbg_writedata[4:0];
					4'd2:  raw_addr_q <= dbg_writedata[8:0];
					4'd3:  if (state == S_IDLE && !start_q) begin
					           raw_wdata_q <= dbg_writedata;
					           eng_addr <= raw_addr_q; eng_wr <= 1'b1;
					           eng_wdata <= dbg_writedata; eng_go <= 1'b1;
					           state <= S_RAW;
					       end
					4'd4:  if (state == S_IDLE && !start_q) begin
					           eng_addr <= raw_addr_q; eng_wr <= 1'b0; eng_go <= 1'b1;
					           state <= S_RAW;
					       end
					4'd8:  m_q <= dbg_writedata[17:0];
					4'd9:  n_q <= dbg_writedata[17:0];
					4'd10: c_q <= dbg_writedata[17:0];
					4'd12: if (state == S_IDLE) start_q <= 1'b1;
					default: ;
				endcase
			end

			case (state)
				S_INIT: begin   // INIT_DELAY Takte mit Lock abwarten, dann einlesen
					wait_cnt <= locked_s ? wait_cnt + 1'd1 : 24'd0;
					if (locked_s && wait_cnt >= INIT_DELAY) begin
						eng_addr <= reg_addr(init_k); eng_wr <= 1'b0; eng_go <= 1'b1;
						state <= S_INIT_A;
					end
				end

				S_INIT_A:
					if (eng_done) begin
						init_a <= eng_rdata;
						eng_addr <= reg_addr(init_k); eng_wr <= 1'b0; eng_go <= 1'b1;
						state <= S_INIT_B;
					end

				S_INIT_B:
					if (eng_done) begin
						if (eng_rdata == 32'hFFFF_FFFF) begin   // Port nicht bereit: warten
							wait_cnt <= 24'd0;
							state <= S_INIT;
						end else if (eng_rdata == init_a) begin     // zweimal gleich: übernehmen
							hw_q[init_k] <= eng_rdata;
							if (init_k == 3'd7) state <= S_IDLE;
							else begin
								init_k <= init_k + 1'd1;
								eng_addr <= reg_addr(init_k + 1'd1); eng_wr <= 1'b0; eng_go <= 1'b1;
								state <= S_INIT_A;
							end
						end else begin                     // verschieden: noch einmal
							eng_addr <= reg_addr(init_k); eng_wr <= 1'b0; eng_go <= 1'b1;
							state <= S_INIT_A;
						end
					end

				S_IDLE:
					if (start_q | start_pend_q) begin
						start_pend_q <= 1'b0;
						cnt_start_q <= cnt_start_q + 1'd1;
						tmo_q <= 1'b0;
						vfail_q <= 1'b0;
						retry_q <= 4'd0;
						step  <= 4'd0;
						state <= S_STEP;
					end

				S_RAW:
					if (eng_done) begin
						if (~eng_wr) rd_word_q <= eng_rdata;
						else if (reg_idx(eng_addr) != 4'hF) hw_q[reg_idx(eng_addr)] <= eng_wdata;
						state <= S_IDLE;
					end

				S_STEP:
					if (step == 4'd9) begin
						wait_cnt <= 24'd0;
						state <= S_LOCK;
					end else if (step == 4'd15) begin
						cnt_done_q <= cnt_done_q + 1'd1;
						state <= S_IDLE;
					end else if (step == 4'd10 && ctrl_q[4]) begin
						step <= 4'd11;
					end else if (step >= 4'd12) begin
						step_k <= reg_idx(rmw_addr);
						eng_addr <= rmw_addr; eng_wr <= 1'b0; eng_go <= 1'b1;
						state <= S_VERIFY;
					end else begin
						// aus dem gemerkten Stand: fremde Bits bleiben, eigene neu
						step_k <= reg_idx(rmw_addr);
						eng_addr  <= rmw_addr;
						eng_wdata <= (hw_q[reg_idx(rmw_addr)] & ~rmw_mask) | (rmw_val & rmw_mask);
						eng_wr <= 1'b1; eng_go <= 1'b1;
						state <= S_WR;
					end

				S_WR:
					if (eng_done) begin
						hw_q[step_k] <= eng_wdata;
						step  <= step + 1'd1;
						state <= (step == 4'd5) ? S_WAIT : S_STEP;   // nach Reset-Bit: Pause
						wait_cnt <= 24'd0;
					end

				S_VERIFY:
					if (eng_done) begin
						if (eng_rdata == hw_q[step_k])
							step <= step + 1'd1;           // stimmt: weiter
						else if (retry_q != MAX_TRIES - 1'd1) begin
							retry_q <= retry_q + 1'd1;     // falsch: nach Pause von vorn
							cnt_retry_q <= cnt_retry_q + 1'd1;
							step <= 4'd0;
						end else begin
							vfail_q <= 1'b1;               // aufgeben
							step <= 4'd15;
						end
						wait_cnt <= 24'd0;
						state <= (eng_rdata == hw_q[step_k] || retry_q == MAX_TRIES - 1'd1) ? S_STEP : S_PAUSE;
					end

				S_PAUSE: begin
					wait_cnt <= wait_cnt + 1'd1;
					if (wait_cnt >= RETRY_PAUSE) state <= S_STEP;
				end

				S_WAIT: begin   // Reset-Puls: >= 10 ns, hier 1 µs
					wait_cnt <= wait_cnt + 1'd1;
					if (wait_cnt == 24'd50) state <= S_STEP;
				end

				S_LOCK: begin
					wait_cnt <= wait_cnt + 1'd1;
					if (wait_cnt >= LOCK_WAIT_MIN && locked_s) begin
						step <= 4'd10; state <= S_STEP;
					end else if (wait_cnt == LOCK_TIMEOUT) begin
						tmo_q <= 1'b1;
						cnt_tmo_q <= cnt_tmo_q + 1'd1;
						step <= 4'd10; state <= S_STEP;
					end
				end

				default: state <= S_IDLE;
			endcase
		end
	end

	// --- Debug lesen ---------------------------------------------------------
	always @(posedge clk) begin
		if (dbg_read) begin
			case (dbg_address)
				4'd0:  dbg_readdata <= {16'h504C, 8'd0, state[3:0], vfail_q, tmo_q, locked_s, state != S_IDLE};
				4'd1:  dbg_readdata <= {27'd0, ctrl_q};
				4'd2:  dbg_readdata <= {23'd0, raw_addr_q};
				4'd3:  dbg_readdata <= rd_word_q;
				4'd5:  dbg_readdata <= cap_q[31:0];
				4'd6:  dbg_readdata <= cap_q[63:32];
				4'd7:  dbg_readdata <= cap_q[95:64];
				4'd8:  dbg_readdata <= {14'd0, m_q};
				4'd9:  dbg_readdata <= {14'd0, n_q};
				4'd10: dbg_readdata <= {14'd0, c_q};
				4'd11: dbg_readdata <= {cnt_retry_q, cnt_tmo_q, cnt_done_q, cnt_start_q};
				4'd13: dbg_readdata <= {16'd0, cap_q[111:96]};
				default: dbg_readdata <= 32'd0;
			endcase
		end
	end

endmodule

`default_nettype wire
