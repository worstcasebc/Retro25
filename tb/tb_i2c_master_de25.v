// SPDX-License-Identifier: GPL-3.0-or-later
// tb_i2c_master_de25 — Testbench für sys/de25/i2c_master_de25.v mit
// tb/i2c_smbus_model.v (ADV7513-Hauptadresse 0x39).
//
// Prüft: Kennung, own/Viertelperiode; SMBus-Schreiben eines Registers;
// SMBus-Lesen (Repeated Start, NACK am Ende); zwei Bytes lesen (ACK, NACK);
// fremde Adresse -> NACK gemeldet; Anzahl Start-/Stoppbedingungen (keine
// ungewollten durch SDA-Wechsel bei SCL = 1).

`timescale 1ns/1ps
`default_nettype none

module tb_i2c_master_de25;

	reg clk = 0;
	always #10 clk = ~clk;   // 50 MHz
	reg rst = 1;

	reg   [3:0] address = 0;
	reg         write = 0, read = 0;
	reg  [31:0] writedata = 0;
	wire [31:0] readdata;
	wire        own, scl_oe, sda_oe;
	wire        slave_low;

	wire scl = ~scl_oe;
	wire sda = ~(sda_oe | slave_low);

	i2c_master_de25 #(.QUARTER(16'd5)) dut (
		.clk(clk), .rst(rst),
		.address(address), .write(write), .writedata(writedata), .read(read), .readdata(readdata),
		.own(own), .scl_oe(scl_oe), .sda_oe(sda_oe), .sda_in(sda),
		.scl_in(scl), .diag_in(3'b101)
	);

	i2c_smbus_model #(.ADDR(7'h39)) adv (.scl(scl), .sda(sda), .sda_low(slave_low));

	integer fails = 0;
	reg [31:0] v;

	task check(input [31:0] got, input [31:0] exp, input [8*40-1:0] msg);
		if (got !== exp) begin
			$display("FAIL: %0s: 0x%08X statt 0x%08X", msg, got, exp);
			fails = fails + 1;
		end
	endtask

	task rd(input [3:0] a, output [31:0] d);
		begin
			@(posedge clk) begin address <= a; read <= 1; end
			@(posedge clk) read <= 0;
			@(negedge clk) d = readdata;
		end
	endtask

	task wr(input [3:0] a, input [31:0] d);
		begin
			@(posedge clk) begin address <= a; writedata <= d; write <= 1; end
			@(posedge clk) write <= 0;
		end
	endtask

	// ein Byte: start, stop, lesen, nack senden
	task cmd(input [7:0] b, input s, input p, input r, input n);
		begin
			wr(4'd0, {20'd0, n, r, p, s, b});
			v = 32'h100;
			while (v[8]) rd(4'd0, v);
		end
	endtask

	initial begin
		$dumpfile("tb/build/tb_i2c_master_de25.vcd");
		$dumpvars(0, tb_i2c_master_de25);
		repeat (3) @(posedge clk);
		rst <= 0;
		repeat (3) @(posedge clk);
		adv.n_stop = 0;   // X -> 1 beim Reset zählt das Modell als Stopp
		adv.n_start = 0;

		rd(4'd0, v);
		check(v[31:24], 8'h49, "Kennung");
		check(own, 0, "own nach Reset");
		wr(4'd1, 32'h0000_0001);
		rd(4'd1, v);
		check(v, 32'h0000_0001, "ctrl");
		check(own, 1, "own gesetzt");
		rd(4'd0, v);
		check(v[23:17], 7'b0011101, "Pins frei, diag_in");
		// Bit-Bang: SDA ziehen, dann SCL ziehen, Pegel zurücklesen
		wr(4'd1, 32'h0000_000B);
		repeat (4) @(posedge clk);
		rd(4'd0, v);
		check(v[23:20], 4'b1010, "Bit-Bang SDA unten");
		wr(4'd1, 32'h0000_0007);
		repeat (4) @(posedge clk);
		rd(4'd0, v);
		check(v[23:20], 4'b0101, "Bit-Bang SCL unten");
		wr(4'd1, 32'h0000_0003);   // beide los
		repeat (4) @(posedge clk);
		wr(4'd1, 32'h0000_0001);
		adv.n_start = 0; adv.n_stop = 0;

		// 1) Register 0x41 = 0x10 schreiben
		cmd(8'h72, 1, 0, 0, 0);
		check(v[9], 0, "ACK Adresse");
		cmd(8'h41, 0, 0, 0, 0);
		cmd(8'h10, 0, 1, 0, 0);
		check(v[9], 0, "ACK Daten");
		check(adv.mem[8'h41], 8'h10, "Register 0x41 geschrieben");

		// 2) Register 0x41 lesen
		cmd(8'h72, 1, 0, 0, 0);
		cmd(8'h41, 0, 0, 0, 0);
		cmd(8'h73, 1, 0, 0, 0);
		check(v[9], 0, "ACK Leseadresse");
		cmd(8'h00, 0, 1, 1, 1);
		check(v[7:0], 8'h10, "Register 0x41 gelesen");

		// 3) zwei Bytes ab 0x00 lesen
		cmd(8'h72, 1, 0, 0, 0);
		cmd(8'h00, 0, 0, 0, 0);
		cmd(8'h73, 1, 0, 0, 0);
		cmd(8'h00, 0, 0, 1, 0);
		check(v[7:0], 8'h5A, "Byte 0");
		cmd(8'h00, 0, 1, 1, 1);
		check(v[7:0], 8'h5B, "Byte 1");

		// 4) fremde Adresse
		cmd(8'h74, 1, 1, 0, 0);
		check(v[9], 1, "NACK fremde Adresse");

		repeat (50) @(posedge clk);
		check(adv.n_start, 6, "Startbedingungen");
		check(adv.n_stop, 4, "Stoppbedingungen");
		check(adv.n_wr, 1, "Schreibbytes im Baustein");

		if (fails == 0) $display("PASS: tb_i2c_master_de25");
		$finish;
	end

	initial begin
		#2_000_000;
		$display("FAIL: Zeitüberschreitung");
		$finish;
	end

endmodule

`default_nettype wire
