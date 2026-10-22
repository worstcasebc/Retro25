// SPDX-License-Identifier: GPL-3.0-or-later
// Übernommen aus C64-DE25 (gleicher Autor).
// i2c_slave_model — Hilfsmodul für Testbenches (nicht synthetisierbar).
//
// Einfacher I2C-Baustein, der Schreibzugriffe der Form
//   Start, DEV_ADDR, Registeradresse, Datenbyte, Stopp
// annimmt, jedes Byte bestätigt und den Wert in mem[] ablegt.
// Fremde Adressen und alles bei force_nack = 1 werden nicht bestätigt.
// sda_low = 1: der Baustein zieht SDA auf 0.

`timescale 1ns / 1ps
`default_nettype none

module i2c_slave_model #(
    parameter [7:0] DEV_ADDR = 8'h72
) (
    input  wire        scl,
    input  wire        sda,
    input  wire        force_nack,
    output reg         sda_low,
    output reg  [31:0] n_writes,    // vollständig empfangene Schreibzugriffe
    output reg  [7:0]  last_reg,
    output reg  [7:0]  last_data
);

    reg [7:0] mem [0:255];

    reg       active    = 1'b0;
    reg       addressed = 1'b0;
    reg [3:0] bit_cnt   = 4'd0;
    reg [1:0] byte_cnt  = 2'd0;
    reg [7:0] shift     = 8'h00;
    reg [7:0] reg_addr  = 8'h00;
    reg [7:0] data      = 8'h00;

    initial begin
        sda_low   = 1'b0;
        n_writes  = 0;
        last_reg  = 8'h00;
        last_data = 8'h00;
    end

    // Start: SDA fällt, während SCL 1 ist.
    always @(negedge sda) begin
        if (scl === 1'b1) begin
            active    = 1'b1;
            addressed = 1'b0;
            bit_cnt   = 4'd0;
            byte_cnt  = 2'd0;
        end
    end

    // Stopp: SDA steigt, während SCL 1 ist.
    always @(posedge sda) begin
        if (scl === 1'b1) begin
            if (active && addressed && byte_cnt == 2'd3) begin
                mem[reg_addr] = data;
                last_reg      = reg_addr;
                last_data     = data;
                n_writes      = n_writes + 1;
            end
            active = 1'b0;
        end
    end

    // Steigende SCL-Flanke: Bit übernehmen (das 9. ist das ACK-Bit).
    always @(posedge scl) begin
        if (active) begin
            if (bit_cnt < 4'd8) begin
                shift   = {shift[6:0], sda};
                bit_cnt = bit_cnt + 4'd1;
            end else begin
                bit_cnt  = 4'd0;
                byte_cnt = byte_cnt + 2'd1;
            end
        end
    end

    // Fallende SCL-Flanke: nach dem 8. Bit bestätigen, sonst loslassen.
    always @(negedge scl) begin
        if (active && bit_cnt == 4'd8) begin
            case (byte_cnt)
                2'd0:    addressed = (shift == DEV_ADDR) && !force_nack;
                2'd1:    reg_addr  = shift;
                default: data      = shift;
            endcase
            sda_low = addressed;
        end else begin
            sda_low = 1'b0;
        end
    end

endmodule

`default_nettype wire
