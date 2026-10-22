// SPDX-License-Identifier: GPL-3.0-or-later
// tb_f2s_halt_de25 — Testbench für sys/de25/f2s_halt_de25.v.
//
// Prüft:
//  1. Durchreichen: Schreib-Bursts und Lese-Bursts kommen unverändert an
//     (Speichermodell mit zufälligem waitrequest und Leselatenz).
//  2. halt mitten im Verkehr: Der Master wird nur zwischen zwei Befehlen
//     angehalten (ein angefangener Schreib-Burst läuft zu Ende, ein wartender
//     Befehl bleibt stehen, bis er angenommen ist); idle kommt erst, wenn
//     alle Lesedaten zurück sind und die Ruhezeit um ist.
//  3. halt wieder weg: der Verkehr läuft weiter, Daten stimmen.
//  4. takeover (TAKEOVER=1): Der Master bricht mitten im Schreib-Burst ab
//     (Core-Reset). Das Modul schreibt den Burst mit byteenable = 0 zu Ende,
//     der Speicher bleibt unverändert, danach idle.
//  5. takeover, während ein Lesebefehl wartet: er wird zu Ende gestellt,
//     seine Daten abgewartet.
// Auf der Speicherseite prüft ein Protokollwächter: kein Burst wird
// abgebrochen, ein wartender Befehl ändert sich nicht, bis er angenommen ist.

`timescale 1ns/1ps
`default_nettype none

module tb_f2s_halt_de25;

	localparam DW = 64, BW = 8, QUIET = 16;

	reg clk = 0;
	always #5 clk = ~clk;

	reg rst = 1, halt = 0, takeover = 0;

	// Master-Seite (Testbench = Core bzw. ascal)
	reg  [31:0] s_address = 0;
	reg   [7:0] s_burstcount = 1;
	reg         s_read = 0, s_write = 0;
	reg  [DW-1:0] s_writedata = 0;
	reg  [BW-1:0] s_byteenable = {BW{1'b1}};
	wire        s_waitrequest;
	wire [DW-1:0] s_readdata;
	wire        s_readdatavalid;

	// Speicher-Seite
	wire [31:0] m_address;
	wire  [7:0] m_burstcount;
	wire        m_read, m_write;
	wire [DW-1:0] m_writedata;
	wire [BW-1:0] m_byteenable;
	reg         m_waitrequest = 0;
	reg  [DW-1:0] m_readdata = 0;
	reg         m_readdatavalid = 0;
	wire        idle;

	f2s_halt_de25 #(.DW(DW), .TAKEOVER(1), .QUIET(QUIET)) dut (
		.clk(clk), .rst(rst), .halt(halt), .takeover(takeover), .idle(idle),
		.s_address(s_address), .s_burstcount(s_burstcount), .s_read(s_read), .s_write(s_write),
		.s_writedata(s_writedata), .s_byteenable(s_byteenable), .s_waitrequest(s_waitrequest),
		.s_readdata(s_readdata), .s_readdatavalid(s_readdatavalid),
		.m_address(m_address), .m_burstcount(m_burstcount), .m_read(m_read), .m_write(m_write),
		.m_writedata(m_writedata), .m_byteenable(m_byteenable), .m_waitrequest(m_waitrequest),
		.m_readdata(m_readdata), .m_readdatavalid(m_readdatavalid)
	);

	integer fails = 0;

	// ---------------- Speichermodell + Protokollwächter ----------------
	reg [DW-1:0] mem [0:255];
	integer i;
	initial for (i = 0; i < 256; i = i + 1) mem[i] = {32'hA5A5_0000 | i, 32'h5A5A_0000 | i};

	// zufälliges waitrequest (etwa jeder dritte Takt)
	integer seed = 7;
	always @(posedge clk) m_waitrequest <= ($random(seed) % 3) == 0;

	// Schreib-Burst
	reg  [7:0] wb_left = 0;
	reg  [7:0] wb_addr = 0;
	// wartender Befehl
	reg        held = 0;
	reg [31:0] held_addr;
	reg  [7:0] held_bc;
	reg        held_rd, held_wr;
	// Lese-Warteschlange (Adresse, Länge), Latenz 5 Takte
	reg  [7:0] rq_addr [0:63];
	reg  [7:0] rq_len  [0:63];
	integer    rq_wr = 0, rq_rd = 0;
	reg  [7:0] rd_left = 0, rd_addr = 0;
	integer    rd_delay = 0;
	integer    reads_out = 0;     // offene Lese-Beats

	always @(posedge clk) begin
		if (!rst) begin
			// Wächter: wartender Befehl muss gleich bleiben
			if (held) begin
				if (!(m_read === held_rd && m_write === held_wr && (m_write && wb_left != 0 ||
				      (m_address === held_addr && m_burstcount === held_bc)))) begin
					$display("FAIL: wartender Befehl verändert (rd %b->%b wr %b->%b a %h->%h bc %0d->%0d) @%0t",
						held_rd, m_read, held_wr, m_write, held_addr, m_address, held_bc, m_burstcount, $time);
					fails = fails + 1;
				end
			end
			if (m_read && m_write) begin
				$display("FAIL: read und write gleichzeitig @%0t", $time); fails = fails + 1;
			end
			if (m_read && wb_left != 0) begin
				$display("FAIL: Lesen mitten im Schreib-Burst @%0t", $time); fails = fails + 1;
			end
			held <= (m_read || m_write) && m_waitrequest;
			held_addr <= m_address; held_bc <= m_burstcount; held_rd <= m_read; held_wr <= m_write;

			// Annahme
			if (m_write && !m_waitrequest) begin
				if (wb_left == 0) begin
					if (m_byteenable != 0) mem[m_address[10:3]] <= m_writedata;
					wb_left <= m_burstcount - 1;
					wb_addr <= m_address[10:3] + 1;
				end else begin
					if (m_byteenable != 0) mem[wb_addr] <= m_writedata;
					wb_left <= wb_left - 1;
					wb_addr <= wb_addr + 1;
				end
			end
			if (m_read && !m_waitrequest) begin
				rq_addr[rq_wr % 64] = m_address[10:3];
				rq_len[rq_wr % 64]  = m_burstcount;
				rq_wr = rq_wr + 1;
				reads_out = reads_out + m_burstcount;
			end
		end

		// Lesedaten liefern
		m_readdatavalid <= 0;
		if (rd_left != 0) begin
			m_readdata <= mem[rd_addr];
			m_readdatavalid <= 1;
			rd_addr <= rd_addr + 1;
			rd_left <= rd_left - 1;
			reads_out = reads_out - 1;
		end else if (rq_rd != rq_wr) begin
			if (rd_delay < 5) rd_delay = rd_delay + 1;
			else begin
				rd_delay = 0;
				rd_addr <= rq_addr[rq_rd % 64];
				rd_left <= rq_len[rq_rd % 64];
				rq_rd = rq_rd + 1;
			end
		end
	end

	// ---------------- Master-Aufgaben ----------------
	reg [DW-1:0] rbuf [0:63];
	integer rcnt = 0;
	always @(posedge clk) if (s_readdatavalid) begin rbuf[rcnt % 64] <= s_readdata; rcnt = rcnt + 1; end

	function [DW-1:0] pat(input [7:0] a, input [7:0] k);
		pat = {24'hC0FFEE, a, 24'hBEEF00, k};
	endfunction

	// Schreib-Burst; abort_after > 0: nach so vielen Beats abbrechen
	task wburst(input [7:0] a, input [7:0] n, input [7:0] k, input integer abort_after);
		integer b;
		begin
			b = 0;
			@(posedge clk);
			s_address <= {21'd0, a, 3'b000}; s_burstcount <= n; s_byteenable <= {BW{1'b1}};
			while (b < n && !(abort_after > 0 && b == abort_after)) begin
				s_write <= 1; s_writedata <= pat(a + b, k);
				@(posedge clk);
				if (!s_waitrequest) b = b + 1;
			end
			s_write <= 0;
		end
	endtask

	// Lese-Burst, wartet auf alle Daten und vergleicht mit erwartet
	task rburst(input [7:0] a, input [7:0] n, input [7:0] k);
		integer b, r0;
		begin
			@(posedge clk);
			s_address <= {21'd0, a, 3'b000}; s_burstcount <= n; s_read <= 1;
			r0 = rcnt;
			@(posedge clk);
			while (s_waitrequest) @(posedge clk);
			s_read <= 0;
			while (rcnt < r0 + n) @(posedge clk);
			#1;   // letzte Daten (nichtblockierend) abwarten
			for (b = 0; b < n; b = b + 1)
				if (rbuf[(r0 + b) % 64] !== pat(a + b, k)) begin
					$display("FAIL: Lesen %0d: %h statt %h", a + b, rbuf[(r0 + b) % 64], pat(a + b, k));
					fails = fails + 1;
				end
		end
	endtask

	task wait_idle(input integer max);
		integer t;
		begin
			t = 0;
			while (!idle && t < max) begin @(posedge clk); t = t + 1; end
			if (!idle) begin $display("FAIL: idle kommt nicht"); fails = fails + 1; end
		end
	endtask

	integer t, wr_seen;
	// Abdeckung: Ersatz-Beats und Ersatz-Lesebefehle des Takeovers
	integer rep_wr_beats = 0, rep_rd_cmds = 0;
	always @(posedge clk) begin
		if (dut.blk_q && m_write && !m_waitrequest) rep_wr_beats = rep_wr_beats + 1;
		if (dut.blk_q && m_read && !m_waitrequest) rep_rd_cmds = rep_rd_cmds + 1;
	end
	reg [DW-1:0] before;

	initial begin
		$dumpfile("tb/build/tb_f2s_halt_de25.vcd");
		$dumpvars(0, tb_f2s_halt_de25);
		repeat (4) @(posedge clk);
		rst <= 0;
		repeat (4) @(posedge clk);

		// 1. Durchreichen
		if (idle) begin $display("FAIL: idle ohne halt"); fails = fails + 1; end
		wburst(8'd16, 8'd8, 8'd1, 0);
		wburst(8'd40, 8'd1, 8'd1, 0);
		rburst(8'd16, 8'd8, 8'd1);
		rburst(8'd40, 8'd1, 8'd1);
		$display("1. Durchreichen geprüft");

		// 2. halt während eines langen Schreib-Bursts: läuft zu Ende
		fork
			wburst(8'd64, 8'd32, 8'd2, 0);
			begin repeat (6) @(posedge clk); halt <= 1; end
		join
		if (idle) begin $display("FAIL: idle sofort nach dem Burst (Ruhezeit fehlt)"); fails = fails + 1; end
		wait_idle(200);
		if (reads_out != 0) begin $display("FAIL: idle mit offenen Lesedaten"); fails = fails + 1; end
		// Ein neuer Befehl wird jetzt nicht angenommen
		@(posedge clk); s_address <= 32'd0; s_burstcount <= 4; s_read <= 1;
		repeat (20) begin
			@(posedge clk);
			if (m_read) begin $display("FAIL: Lesen trotz halt weitergegeben"); fails = fails + 1; end
			if (!s_waitrequest) begin $display("FAIL: Befehl trotz halt angenommen"); fails = fails + 1; end
		end
		// 3. halt weg: der wartende Lesebefehl läuft, danach Daten prüfen
		halt <= 0;
		@(posedge clk); while (s_waitrequest) @(posedge clk);
		s_read <= 0;
		t = rcnt; while (rcnt < t + 4) @(posedge clk);
		rburst(8'd64, 8'd32, 8'd2);
		$display("2./3. halt und Freigabe geprüft");

		// 2b. halt, während ein Lese-Burst Daten liefert: idle erst danach
		fork
			rburst(8'd64, 8'd32, 8'd2);
			begin repeat (3) @(posedge clk); halt <= 1; end
		join
		wait_idle(200);
		if (reads_out != 0) begin $display("FAIL: idle mit offenen Lesedaten"); fails = fails + 1; end
		halt <= 0;
		repeat (4) @(posedge clk);
		if (idle) begin $display("FAIL: idle bleibt nach halt=0"); fails = fails + 1; end

		// 4. takeover mitten im Schreib-Burst: Master bricht nach 5 Beats ab
		before = mem[100 + 7];
		fork
			wburst(8'd100, 8'd16, 8'd3, 5);
			begin
				@(posedge clk); while (!(s_write && !s_waitrequest)) @(posedge clk);
				repeat (4) @(posedge clk);
				takeover <= 1;
			end
		join
		wait_idle(400);
		if (mem[100 + 7] !== before) begin $display("FAIL: Ersatz-Beats haben geschrieben"); fails = fails + 1; end
		if (wb_left != 0) begin $display("FAIL: Burst nicht zu Ende geschrieben (%0d offen)", wb_left); fails = fails + 1; end
		takeover <= 0;
		repeat (4) @(posedge clk);
		rburst(8'd100, 8'd4, 8'd3);   // die ersten Beats kamen an
		if (rep_wr_beats == 0) begin $display("FAIL: keine Ersatz-Beats"); fails = fails + 1; end
		$display("4. takeover im Schreib-Burst geprüft (%0d Ersatz-Beats)", rep_wr_beats);

		// 5. takeover, während ein Lesebefehl wartet
		@(posedge m_waitrequest);
		@(negedge clk);
		s_address <= {21'd0, 8'd16, 3'b000}; s_burstcount <= 8; s_read <= 1; takeover <= 1;
		@(posedge clk); s_read <= 0;  // Master im Reset: lässt sofort los
		wait_idle(400);
		if (reads_out != 0) begin $display("FAIL: idle mit offenen Lesedaten"); fails = fails + 1; end
		takeover <= 0;
		repeat (4) @(posedge clk);
		rburst(8'd16, 8'd8, 8'd1);
		if (rep_rd_cmds != 1) begin $display("FAIL: %0d Ersatz-Lesebefehle statt 1", rep_rd_cmds); fails = fails + 1; end
		$display("5. takeover bei wartendem Lesebefehl geprüft");

		if (fails == 0) $display("PASS: tb_f2s_halt_de25");
		else $display("FAIL: %0d Fehler", fails);
		$finish;
	end

	initial begin #400000; $display("FAIL: Zeitüberschreitung"); $finish; end

endmodule

`default_nettype wire
