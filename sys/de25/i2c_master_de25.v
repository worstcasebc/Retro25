// SPDX-License-Identifier: GPL-3.0-or-later
// i2c_master_de25 — byteweiser I2C-Master für Main_MiSTer (HDMI-Sender).
//
// Zweck:  Main stellt den ADV7513 wie bei MiSTer selbst ein. Dessen I2C hängt
//         beim DE25-Nano an FPGA-Pins; Linux erreicht ihn über diese Register
//         (LW-Bridge, linux/main/de25/smbus.cpp). Ein Befehl = ein Byte,
//         wahlweise mit Start (bzw. Repeated Start) davor und Stopp danach —
//         daraus baut die Software SMBus-Zugriffe zusammen.
// Register (Wortadressen, Lesedaten einen Takt nach rd):
//   0  W  Befehl: [7:0] Byte (Schreiben), [8] Start davor, [9] Stopp danach,
//                 [10] Lesen statt Schreiben, [11] beim Lesen NACK senden
//                 (letztes Byte), sonst ACK. Wird ignoriert, solange busy.
//      R  Status: [7:0] gelesenes Byte, [8] busy, [9] NACK beim letzten
//                 Schreibbyte, [16] own, [19:17] diag_in (von außen, z. B.
//                 Zustand von hdmi_config), [20] SDA am Pin, [21] SCL am
//                 Pin, [22] scl_oe, [23] sda_oe, [31:24] 0x49 ("I")
//   1  RW [0] own: Master treibt die Pins (sonst hdmi_config),
//         [1] Bit-Bang zur Fehlersuche: solange nicht busy, gilt
//             scl_oe = [2], sda_oe = [3] (1 = auf 0 ziehen),
//         [31:16] Viertelperiode in Takten (0 = Standard QUARTER)
// Pins:   scl_oe/sda_oe = 1 zieht die Leitung auf 0 (Open Drain), sda_in
//         asynchron (2 FF). Kein Clock Stretching (SCL ist nur Ausgang).
// Takt:   clk (50 MHz: QUARTER 125 = 100 kHz).
// Analogie: Ein Morse-Telegrafist, der immer genau ein Zeichen sendet bzw.
//         empfängt und dann auf den nächsten Auftrag wartet.

`default_nettype none

module i2c_master_de25 #(
	parameter [15:0] QUARTER = 16'd125
) (
	input  wire        clk,
	input  wire        rst,

	input  wire  [3:0] address,
	input  wire        write,
	input  wire [31:0] writedata,
	input  wire        read,
	output reg  [31:0] readdata,

	output wire        own,
	output reg         scl_oe,
	output reg         sda_oe,
	input  wire        sda_in,
	input  wire        scl_in,
	input  wire  [2:0] diag_in
);

	reg        own_q;
	reg  [2:0] bb_q;        // [0] Bit-Bang an, [1] SCL ziehen, [2] SDA ziehen
	reg [15:0] quarter_q;
	assign own = own_q;

	wire sda_s;
	sync_2ff sda_sync(.clk(clk), .d_async(sda_in), .d_sync_q(sda_s));
	wire scl_s;
	sync_2ff scl_sync(.clk(clk), .d_async(scl_in), .d_sync_q(scl_s));

	// Befehl
	reg  [7:0] tx_q, rx_q;
	reg        do_start_q, do_stop_q, do_read_q, nack_out_q, nack_in_q;
	reg        busy_q;

	// Viertelperioden-Takt
	reg [15:0] div_q;
	wire [15:0] quarter = (quarter_q == 16'd0) ? QUARTER : quarter_q;
	wire tick = (div_q == 16'd0);

	// Ablauf: Phase (START, BITS, STOP), Bitnummer, Viertel
	localparam P_START = 2'd0, P_BITS = 2'd1, P_STOP = 2'd2;
	reg [1:0] phase;
	reg [3:0] bitn;     // 0..7 Datenbits, 8 = ACK-Bit
	reg [1:0] q;

	// Bit, das im Datenteil auf SDA liegen soll (1 = loslassen)
	wire out_bit = (bitn == 4'd8) ? (do_read_q ? nack_out_q : 1'b1)
	                              : (do_read_q ? 1'b1 : tx_q[7 - bitn[2:0]]);

	always @(posedge clk) begin
		if (rst) begin
			own_q <= 1'b0;
			bb_q <= 3'd0;
			quarter_q <= 16'd0;
			busy_q <= 1'b0;
			scl_oe <= 1'b0;
			sda_oe <= 1'b0;
			nack_in_q <= 1'b0;
			div_q <= 16'd0;
		end else begin
			if (write && address == 4'd1) begin
				own_q <= writedata[0];
				bb_q  <= writedata[3:1];
				quarter_q <= writedata[31:16];
			end

			if (!busy_q) begin
				div_q <= 16'd0;
				if (bb_q[0]) begin
					scl_oe <= bb_q[1];
					sda_oe <= bb_q[2];
				end
				if (write && address == 4'd0) begin
					tx_q       <= writedata[7:0];
					do_start_q <= writedata[8];
					do_stop_q  <= writedata[9];
					do_read_q  <= writedata[10];
					nack_out_q <= writedata[11];
					phase <= writedata[8] ? P_START : P_BITS;
					bitn  <= 4'd0;
					q     <= 2'd0;
					busy_q <= 1'b1;
				end
			end else begin
				div_q <= tick ? quarter - 1'd1 : div_q - 1'd1;
				if (tick) begin
					q <= q + 1'd1;
					case (phase)
						P_START: case (q)   // SDA los, SCL los, SDA runter, SCL runter
							2'd0: sda_oe <= 1'b0;
							2'd1: scl_oe <= 1'b0;
							2'd2: sda_oe <= 1'b1;
							2'd3: begin scl_oe <= 1'b1; phase <= P_BITS; end
						endcase
						P_BITS: case (q)    // Daten setzen, SCL hoch, abtasten, SCL runter
							2'd0: sda_oe <= ~out_bit;
							2'd1: scl_oe <= 1'b0;
							2'd2: begin
								if (bitn == 4'd8) begin
									if (!do_read_q) nack_in_q <= sda_s;
								end else
									rx_q <= {rx_q[6:0], sda_s};
							end
							2'd3: begin
								scl_oe <= 1'b1;
								if (bitn == 4'd8) begin
									if (do_stop_q) phase <= P_STOP;
									else busy_q <= 1'b0;   // SCL bleibt unten, SDA wie es ist
									                       // (nicht mit der SCL-Flanke ändern)
								end
								bitn <= bitn + 1'd1;
							end
						endcase
						P_STOP: case (q)    // SDA runter, SCL los, SDA los
							2'd0: sda_oe <= 1'b1;
							2'd1: scl_oe <= 1'b0;
							2'd2: sda_oe <= 1'b0;
							2'd3: busy_q <= 1'b0;
						endcase
						default: busy_q <= 1'b0;
					endcase
				end
			end
		end
	end

	always @(posedge clk) begin
		if (read) begin
			case (address)
				4'd0: readdata <= {8'h49, sda_oe, scl_oe, scl_s, sda_s, diag_in, own_q,
				                   6'd0, nack_in_q, busy_q, rx_q};
				4'd1: readdata <= {quarter_q, 12'd0, bb_q, own_q};
				default: readdata <= 32'd0;
			endcase
		end
	end

endmodule

`default_nettype wire
