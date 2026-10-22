// SPDX-License-Identifier: GPL-3.0-or-later
// i2c_smbus_model — I2C-Baustein mit Registerfeld für Testbenches
// (nicht synthetisierbar), Verhalten wie der ADV7513:
//   Schreiben: S, ADDR+W, Register, Daten..., P   (Zeiger zählt hoch)
//   Lesen:     S, ADDR+W, Register, Sr, ADDR+R, Daten... (Master: ACK bzw.
//              NACK nach dem letzten Byte), P
// Fremde Adressen werden nicht bestätigt. sda_low = 1: Baustein zieht SDA.
// Zählt Start-, Repeated-Start- und Stoppbedingungen.

`timescale 1ns / 1ps
`default_nettype none

module i2c_smbus_model #(
	parameter [6:0] ADDR = 7'h39
) (
	input  wire scl,
	input  wire sda,
	output reg  sda_low
);

	reg [7:0] mem [0:255];
	reg [7:0] ptr = 0;
	reg       active = 0, addressed = 0, reading = 0, master_ack = 0;
	reg [3:0] bit_cnt = 0;
	integer   byte_cnt = 0;
	reg [7:0] shift = 0, out_byte = 0;
	integer   n_start = 0, n_stop = 0, n_wr = 0, n_rd = 0;
	integer   i;

	initial begin
		sda_low = 1'b0;
		for (i = 0; i < 256; i = i + 1) mem[i] = i ^ 8'h5A;
	end

	always @(negedge sda) if (scl === 1'b1) begin   // Start / Repeated Start
		active = 1; addressed = 0; reading = 0; bit_cnt = 0; byte_cnt = 0;
		n_start = n_start + 1;
	end

	always @(posedge sda) if (scl === 1'b1) begin   // Stopp
		active = 0; n_stop = n_stop + 1;
	end

	always @(posedge scl) if (active) begin
		if (bit_cnt < 8) begin
			shift = {shift[6:0], sda};
			bit_cnt = bit_cnt + 1;
		end else begin
			master_ack = (sda === 1'b0);   // beim Lesen: ACK des Masters
			bit_cnt = 0;
			byte_cnt = byte_cnt + 1;
		end
	end

	always @(negedge scl) if (active) begin
		if (bit_cnt == 8) begin
			// 9. Bit: Baustein bestätigt (Schreiben) bzw. lässt los (Lesen)
			if (reading) sda_low = 1'b0;
			else begin
				if (byte_cnt == 0) begin
					addressed = (shift[7:1] == ADDR);
					reading   = addressed & shift[0];
					sda_low   = addressed;
				end else if (addressed) begin
					if (byte_cnt == 1) ptr = shift;
					else begin mem[ptr] = shift; ptr = ptr + 1; n_wr = n_wr + 1; end
					sda_low = 1'b1;
				end else sda_low = 1'b0;
			end
		end else if (reading && bit_cnt == 0 && (byte_cnt == 1 || master_ack)) begin
			// nächstes Byte ausgeben (nach dem Adressbyte bzw. nach ACK)
			out_byte = mem[ptr]; ptr = ptr + 1; n_rd = n_rd + 1;
			sda_low = ~out_byte[7];
		end else if (reading && bit_cnt > 0 && bit_cnt < 8) begin
			sda_low = ~out_byte[7 - bit_cnt];
		end else begin
			sda_low = 1'b0;
			if (reading && bit_cnt == 0) reading = 0;   // NACK: Ende
		end
	end

endmodule

`default_nettype wire
