// SPDX-License-Identifier: GPL-3.0-or-later
// hvio_pll_model — Verhaltensmodell des Umkonfigurations-Ports einer
// Agilex-5-HVIO-IOPLL (core_avl_*), nur für Testbenches.
//
// Nachgebildet nach dem Agilex-5-Clocking-and-PLL-User-Guide (813671,
// Kap. 6.2/6.3, Stand 25.1.1), soweit er eindeutig ist:
//   - 32-bit-Register, übertragen als 4 Bytes über 8-bit-Daten, LSB zuerst
//   - Schreiben: write 10 Takte lang; 5 Takte 0x00, dann b0 b1 b2 b3 b3
//   - Lesen: read 10 Takte lang; 5 Takte ungültig, dann 0x00, b0..b3
//   - danach mindestens 5 Leertakte
//   - Adresse: Serienbausteine Wortadresse (Byte-Offset >> 2), ES-Bausteine
//     Byte-Offset (Parameter ES)
// Wie die Bytes auf der echten Hardware takten, ist im Handbuch nicht ganz
// eindeutig; pll_cfg_de25 zeichnet deshalb die gelesenen Bytes zum Prüfen
// auf dem Board auf. Das Modell meldet Protokollfehler mit "FAIL".
//
// Lock: Reset-Bit (0x80[2]) nimmt locked weg; eine Kalibrieranforderung
// (0x88[11] bei 0x48[14] = 1) setzt es nach LOCK_DELAY Takten wieder.
// Fehlerbilder vom Board (zweite HVIO-PLL wurde gleichzeitig umgestellt):
// drop_5c > 0 verwirft so viele Schreibzugriffe auf 0x5C (C0); bad_rd > 0
// lässt so viele Lesezugriffe nur Nullen liefern (am Board verlor 0x44 so
// seine oberen Bits, weil der falsche Wert zurückgeschrieben wurde).
// Nach dem Laden ist der Port am Board eine Weile nicht bereit: NOT_READY
// Takte lang liefert Lesen nur 0xFF und Schreiben wirkt nicht (locked = 0).

`timescale 1ns/1ps
`default_nettype none

module hvio_pll_model #(
	parameter ES         = 0,
	parameter LOCK_DELAY = 200,
	parameter NOT_READY  = 0
) (
	input  wire       clk,
	input  wire [8:0] address,
	input  wire       read,
	input  wire       write,
	input  wire [7:0] writedata,
	output reg  [7:0] readdata,   // kombinatorisch: Takt i des Lesens = Byte i
	output reg        locked
);

	reg [31:0] regs [0:127];
	integer i;
	integer errors = 0;
	integer writes = 0;
	integer drop_5c = 0;    // Testbench: so viele Schreibzugriffe auf 0x5C verwerfen
	integer bad_rd  = 0;    // Testbench: so viele Lesezugriffe liefern nur Nullen
	integer ready_cnt = NOT_READY;
	wire    not_ready = (ready_cnt > 0);

	initial begin
		for (i = 0; i < 128; i = i + 1) regs[i] = 32'h0;
		// Startwerte wie pll_hdmi_de25 (M 297, N 5 = 3+2 ungerade, C 40 = 20+20)
		regs[8'h40 >> 2] = (32'd297 << 20) | (32'd1 << 17) | (32'd2 << 9) | 32'd3;
		regs[8'h44 >> 2] = 32'h0780_0085;   // wie am Board; obere Bits fremd
		regs[8'h5C >> 2] = (32'd20 << 23) | 32'd20 | 32'h0000_7E00;  // [22:9] fremde Bits
		regs[8'h10 >> 2] = 32'h1234_5600;
		regs[8'h58 >> 2] = 32'h00A0_0081;
		locked   = 1'b1;
	end

	wire [6:0] idx = ES ? address[8:2] : address[6:0];

	reg        wr_q = 0, rd_q = 0;
	integer    cyc = 0, idle = 100;
	reg [31:0] wdata;
	reg [6:0]  op_idx;
	integer    lock_cnt = -1;

	// Lesedaten: im Takt i seit Beginn von read (cyc == i) liegt Byte i an
	always @(*) begin
		if (!read) readdata = 8'hEE;
		else if (not_ready) readdata = 8'hFF;
		else if (bad_rd > 0) readdata = (cyc >= 5 && cyc <= 9) ? 8'h00 : 8'hEE;
		else case (cyc)
			5: readdata = 8'h00;
			6: readdata = regs[op_idx][7:0];
			7: readdata = regs[op_idx][15:8];
			8: readdata = regs[op_idx][23:16];
			9: readdata = regs[op_idx][31:24];
			default: readdata = 8'hEE;   // ungültig
		endcase
	end

	always @(posedge clk) begin
		wr_q <= write;
		rd_q <= read;
		if (rd_q & ~read & (bad_rd > 0) & ~not_ready) bad_rd = bad_rd - 1;
		if (ready_cnt > 0) ready_cnt = ready_cnt - 1;

		if ((write | read) & ~(wr_q | rd_q)) begin
			if (idle < 5) begin
				$display("FAIL: hvio_pll_model: nur %0d Leertakte vor Zugriff", idle);
				errors = errors + 1;
			end
			cyc = 0;
			op_idx = idx;
		end

		if (write & read) begin
			$display("FAIL: hvio_pll_model: read und write gleichzeitig");
			errors = errors + 1;
		end

		if (write) begin
			if ((write & ~wr_q) == 0 && idx != op_idx) begin
				$display("FAIL: hvio_pll_model: Adresse während Schreiben geändert");
				errors = errors + 1;
			end
			if (cyc < 5 && writedata !== 8'h00) begin
				$display("FAIL: hvio_pll_model: Präambel-Byte %0d = %02X", cyc, writedata);
				errors = errors + 1;
			end
			case (cyc)
				5: wdata[7:0]   = writedata;
				6: wdata[15:8]  = writedata;
				7: wdata[23:16] = writedata;
				8: wdata[31:24] = writedata;
				9: if (writedata !== wdata[31:24]) begin
					$display("FAIL: hvio_pll_model: letztes Byte nicht gehalten");
					errors = errors + 1;
				end
			endcase
			cyc = cyc + 1;
			idle = 0;
		end else if (wr_q) begin
			// Ende des Schreibzugriffs: übernehmen
			if (cyc != 10) begin
				$display("FAIL: hvio_pll_model: write %0d statt 10 Takte", cyc);
				errors = errors + 1;
			end else if (not_ready) begin
				;                        // Port noch nicht bereit: wirkungslos
			end else if (op_idx == (8'h5C >> 2) && drop_5c > 0) begin
				drop_5c = drop_5c - 1;   // verloren, ohne Meldung
			end else begin
				regs[op_idx] = wdata;
				writes = writes + 1;
				if (op_idx == (8'h80 >> 2) && wdata[2]) locked = 1'b0;
				if (op_idx == (8'h88 >> 2) && wdata[11] && regs[8'h48 >> 2][14]) lock_cnt = LOCK_DELAY;
			end
			idle = 1;
		end else if (read) begin
			if ((read & ~rd_q) == 0 && idx != op_idx) begin
				$display("FAIL: hvio_pll_model: Adresse während Lesen geändert");
				errors = errors + 1;
			end
			cyc = cyc + 1;
			idle = 0;
		end else begin
			if (rd_q && cyc != 10) begin
				$display("FAIL: hvio_pll_model: read %0d statt 10 Takte", cyc);
				errors = errors + 1;
			end
			idle = idle + 1;
		end

		if (lock_cnt > 0) lock_cnt = lock_cnt - 1;
		else if (lock_cnt == 0) begin
			locked = 1'b1;
			lock_cnt = -1;
		end
	end

endmodule

`default_nettype wire
