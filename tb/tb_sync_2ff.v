// SPDX-License-Identifier: GPL-3.0-or-later
// Übernommen aus C64-DE25 (gleicher Autor).
// tb_sync_2ff — selbstprüfende Testbench für sync_2ff.
//
// Prüft: Eine Eingangsänderung (absichtlich NICHT taktsynchron angelegt)
// erscheint frühestens nach 2 und spätestens nach 3 Taktflanken am Ausgang,
// und alle Bits werden unabhängig durchgereicht.

`timescale 1ns / 1ps
`default_nettype none

module tb_sync_2ff;

    localparam WIDTH = 4;

    reg              clk = 1'b0;
    reg  [WIDTH-1:0] d   = {WIDTH{1'b0}};
    wire [WIDTH-1:0] q;

    integer errors = 0;

    sync_2ff #(.WIDTH(WIDTH)) dut (
        .clk      (clk),
        .d_async  (d),
        .d_sync_q (q)
    );

    always #10 clk = ~clk;   // 50 MHz

    // Legt value 7 ns nach einer Taktflanke an (asynchron zum Takt).
    task apply_and_check(input [WIDTH-1:0] value);
        reg [WIDTH-1:0] old;
        begin
            old = q;
            @(posedge clk);
            #7 d = value;
            @(posedge clk); #1;      // 1. Flanke: erst im meta-Register
            if (q !== old) begin
                $display("FAIL: Ausgang aendert sich schon nach 1 Takt (q=%b) bei t=%0t", q, $time);
                errors = errors + 1;
            end
            @(posedge clk); #1;      // 2. Flanke: am Ausgang
            if (q !== value) begin
                $display("FAIL: q=%b, erwartet %b nach 2 Takten bei t=%0t", q, value, $time);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb/build/tb_sync_2ff.vcd");
        $dumpvars(0, tb_sync_2ff);

        repeat (3) @(posedge clk);   // X-Werte aus den Registern herausschieben
        #1;
        if (q !== {WIDTH{1'b0}}) begin
            $display("FAIL: Startwert q=%b, erwartet 0", q);
            errors = errors + 1;
        end

        apply_and_check(4'b1010);
        apply_and_check(4'b0101);
        apply_and_check(4'b1111);
        apply_and_check(4'b0000);

        if (errors == 0) $display("PASS: tb_sync_2ff");
        else             $display("FAIL: tb_sync_2ff (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
