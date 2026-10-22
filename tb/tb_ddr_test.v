// SPDX-License-Identifier: GPL-3.0-or-later
// tb_ddr_test — Testbench für cores/testpattern/ddr_test.v (P3, Schritt 2c).
//
// Speichermodell: Avalon-MM-Slave wie MiSTers DDRAM-Port (Wortadresse,
// burstcnt mit dem ersten Wort, busy = waitrequest), zufälliges busy und
// zufällige Leselatenz (1..8 Takte bis zum ersten Wort, Lücken im Burst).
// Prüft:
//   1. Lauf 1: alle Adressen genau einmal beschrieben, Muster stimmt, Bursts
//      vollständig, keine Adresse außerhalb [BASE, BASE+WORDS); pass, 0 Fehler
//   2. Lauf 2 mit absichtlich gekipptem Bit an einer Adresse (das Modell
//      verfälscht beim Lesen): genau 1 Fehler, pass = 0
//   3. Lauf 3 ohne Fehler: wieder pass (neues seed, Muster ändert sich)
//   4. Takte fürs Schreiben/Lesen plausibel (> WORDS)
//   5. Reset mitten im Schreib-Burst: der Burst wird trotzdem vollständig
//      geschrieben (sonst wartet die F2SDRAM-Seite ewig auf den Rest und die
//      SMMU des HPS hängt), danach ruht der Test; ein neuer Lauf klappt
//   6. Reset, während ein Lesebefehl wartet: rd bleibt, bis er angenommen ist
// Durchgehend geprüft: ein wartender Befehl (rd/we bei busy) bleibt anliegen.

`timescale 1ns/1ps
`default_nettype none

module tb_ddr_test;

	localparam [28:0] BASE  = 29'h0600_0000;
	localparam        WORDS = 512;
	localparam        BURST = 64;

	reg clk = 1'b0;
	always #6.7 clk = ~clk;                    // ~74,25 MHz

	reg rst = 1'b1, start = 1'b0;

	wire [28:0] addr;
	wire  [7:0] burstcnt;
	wire [63:0] din;
	wire  [7:0] be;
	wire        rd, we;
	reg         busy = 1'b1;
	reg  [63:0] dout = 64'd0;
	reg         dout_ready = 1'b0;

	wire        running, done, pass;
	wire [15:0] err;
	wire [31:0] wr_cycles, rd_cycles;

	ddr_test #(.BASE(BASE), .WORDS(WORDS), .BURST(BURST)) dut (
		.clk(clk), .rst(rst), .start(start),
		.ddram_addr(addr), .ddram_burstcnt(burstcnt), .ddram_busy(busy),
		.ddram_dout(dout), .ddram_dout_ready(dout_ready), .ddram_rd(rd),
		.ddram_din(din), .ddram_be(be), .ddram_we(we),
		.running_q(running), .done_q(done), .pass_q(pass), .err_q(err),
		.wr_cycles_q(wr_cycles), .rd_cycles_q(rd_cycles)
	);

	// --- Speichermodell ------------------------------------------------------
	reg  [63:0] mem    [0:WORDS-1];
	integer     writes [0:WORDS-1];
	integer     fails = 0;
	integer     flip_at = -1;          // Wortindex, dessen Lesewert verfälscht wird

	integer     wr_left = 0;           // Wörter, die im Schreib-Burst noch fehlen
	integer     wr_idx  = 0;
	integer     rd_left = 0, rd_idx = 0, rd_wait = 0;
	integer     i;

	task fail(input [8*80-1:0] msg);
		begin
			$display("FAIL: %0s (t=%0t)", msg, $time);
			fails = fails + 1;
		end
	endtask

	// Avalon: ein Befehl, der bei busy anliegt, muss im nächsten Takt bleiben
	reg held_rd = 0, held_we = 0;
	always @(posedge clk) begin
		if (held_rd && !rd) fail("wartender Lesebefehl zurückgezogen");
		if (held_we && !we) fail("wartendes Schreibwort zurückgezogen");
		held_rd <= rd && busy;
		held_we <= we && busy;
	end

	always @(posedge clk) begin
		// busy zufällig, aber nie, während Lesedaten ausstehen (einfacheres
		// Modell: ein Lese-Burst nach dem anderen — so arbeitet ddr_test).
		busy <= ($random & 3) == 0;

		// Schreiben: Wort übernommen, wenn we && !busy
		if (we && !busy) begin
			if (wr_left == 0) begin
				if (burstcnt != BURST) fail("burstcnt beim Schreiben falsch");
				if (addr < BASE || addr + burstcnt > BASE + WORDS) fail("Schreibadresse außerhalb");
				wr_idx  = addr - BASE;
				wr_left = burstcnt;
			end
			if (wr_idx >= 0 && wr_idx < WORDS) begin
				mem[wr_idx]    <= din;
				writes[wr_idx] = writes[wr_idx] + 1;
			end
			if (be != 8'hFF) fail("byteenable nicht FF");
			wr_idx  = wr_idx + 1;
			wr_left = wr_left - 1;
		end

		// Lesebefehl übernommen, wenn rd && !busy
		if (rd && !busy) begin
			if (rd_left != 0) fail("neuer Lesebefehl vor Ende des Bursts");
			if (burstcnt != BURST) fail("burstcnt beim Lesen falsch");
			if (addr < BASE || addr + burstcnt > BASE + WORDS) fail("Leseadresse außerhalb");
			if (wr_left != 0) fail("Lesen vor Ende des Schreib-Bursts");
			rd_idx  = addr - BASE;
			rd_left = burstcnt;
			rd_wait = 1 + ($random & 7);
		end

		// Lesedaten mit Latenz und Lücken ausgeben
		dout_ready <= 1'b0;
		if (rd_left > 0) begin
			if (rd_wait > 0) rd_wait = rd_wait - 1;
			else if (($random & 3) != 0) begin
				dout       <= mem[rd_idx] ^ ((rd_idx == flip_at) ? 64'h0000_0000_0001_0000 : 64'd0);
				dout_ready <= 1'b1;
				rd_idx  = rd_idx + 1;
				rd_left = rd_left - 1;
			end
		end
	end

	// --- Ablauf ----------------------------------------------------------------
	task run(input integer expect_err);
		begin
			for (i = 0; i < WORDS; i = i + 1) writes[i] = 0;
			@(posedge clk) start <= 1'b1;
			@(posedge clk) start <= 1'b0;
			wait (!done);              // done vom vorigen Lauf erst abwarten
			wait (done);
			@(posedge clk);
			for (i = 0; i < WORDS; i = i + 1)
				if (writes[i] != 1) begin
					fail("Adresse nicht genau einmal beschrieben");
					i = WORDS;
				end
			if (err != expect_err) begin
				$display("  err = %0d, erwartet %0d", err, expect_err);
				fail("Fehlerzahl falsch");
			end
			if (pass != (expect_err == 0)) fail("pass falsch");
			if (wr_cycles < WORDS || rd_cycles < WORDS) fail("Taktzähler unplausibel");
			$display("  Lauf: err=%0d pass=%0d, %0d Takte schreiben, %0d Takte lesen",
			         err, pass, wr_cycles, rd_cycles);
		end
	endtask

	reg [63:0] first_word;

	initial begin
		$dumpfile("tb/build/tb_ddr_test.vcd");
		$dumpvars(0, tb_ddr_test);
		repeat (5) @(posedge clk);
		rst <= 1'b0;

		// 1: fehlerfrei; Muster von Wort 0 und 5 prüfen
		run(0);
		if (mem[0] !== {32'h0000_0000 ^ 32'hA5A5_5A5A, 32'h0000_0000 ^ 32'h1}) fail("Muster Wort 0");
		if (mem[5] !== {32'h0000_0005 ^ 32'hA5A5_5A5A, 32'h0000_0005 ^ 32'h1}) fail("Muster Wort 5");
		first_word = mem[0];

		// 2: ein Bit kippt beim Lesen von Wort 300
		flip_at = 300;
		run(1);
		flip_at = -1;

		// 3: wieder fehlerfrei, neues seed -> anderes Muster
		run(0);
		if (mem[0] === first_word) fail("seed hat sich nicht geändert");

		// 5: Reset mitten im Schreib-Burst
		@(posedge clk) start <= 1'b1;
		@(posedge clk) start <= 1'b0;
		wait (wr_left > 5 && wr_left < BURST - 5);
		@(posedge clk) rst <= 1'b1;
		repeat (3) @(posedge clk);
		rst <= 1'b0;
		repeat (BURST * 4) @(posedge clk);
		if (wr_left != 0) begin
			$display("  %0d Wörter fehlen", wr_left);
			fail("Schreib-Burst nach Reset nicht vollständig");
		end
		if (we || rd || running) fail("nach Reset nicht in Ruhe");
		$display("  Reset im Schreib-Burst: Burst vollständig");
		run(0);

		// 6: Reset, während ein Lesebefehl wartet (Schreibphase abwarten)
		@(posedge clk) start <= 1'b1;
		@(posedge clk) start <= 1'b0;
		wait (rd && busy);
		@(negedge clk) rst <= 1'b1;
		repeat (20) @(posedge clk);
		rst <= 1'b0;
		repeat (20) @(posedge clk);
		if (rd || we) fail("nach Reset im Lesebefehl nicht in Ruhe");
		$display("  Reset bei wartendem Lesebefehl geprüft");
		wait (rd_left == 0);
		run(0);

		if (fails == 0) $display("PASS: tb_ddr_test");
		$finish;
	end

	initial begin
		#5_000_000;
		$display("FAIL: Zeitüberschreitung");
		$finish;
	end

endmodule

`default_nettype wire
