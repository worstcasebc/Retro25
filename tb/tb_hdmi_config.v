// SPDX-License-Identifier: GPL-3.0-or-later
// Übernommen aus C64-DE25 (gleicher Autor).
// tb_hdmi_config — selbstprüfende Testbench für hdmi_config.
//
// Am Bus hängt das Modell i2c_slave_model (Adresse $72).
// 1. Während der Wartezeit nach Reset passiert auf dem Bus nichts.
// 2. Danach werden genau 34 Register geschrieben, erst dann ist ready = 1.
//    Stichproben: Schlafmodus aus ($41), HDMI-Modus ($AF), letztes ($FA).
// 3. Antwortet der Baustein nicht, wird wiederholt, bis er antwortet.
// 4. Ein Interrupt (int_n = 0) löst die Konfiguration erneut aus.

`timescale 1ns / 1ps
`default_nettype none

module tb_hdmi_config;

    localparam STARTUP_CLKS = 200;
    localparam N_REGS       = 34;

    reg         clk        = 1'b0;
    reg         rst        = 1'b1;
    reg         int_n      = 1'b1;
    reg         force_nack = 1'b0;
    wire        scl_oe;
    wire        sda_oe;
    wire        ready;
    wire        nack;
    wire        slave_sda_low;
    wire [31:0] n_writes;
    wire [7:0]  last_reg;
    wire [7:0]  last_data;

    // Der Bus mit Pull-up: 1, solange niemand zieht.
    wire scl = ~scl_oe;
    wire sda = ~(sda_oe | slave_sda_low);

    integer errors = 0;

    hdmi_config #(.CLKS_PER_QUARTER(4), .STARTUP_CLKS(STARTUP_CLKS)) dut (
        .clk      (clk),
        .rst      (rst),
        .int_n    (int_n),
        .scl_oe_q (scl_oe),
        .sda_oe_q (sda_oe),
        .sda_in   (sda),
        .ready_q  (ready),
        .nack_q   (nack)
    );

    i2c_slave_model slave (
        .scl        (scl),
        .sda        (sda),
        .force_nack (force_nack),
        .sda_low    (slave_sda_low),
        .n_writes   (n_writes),
        .last_reg   (last_reg),
        .last_data  (last_data)
    );

    always #10 clk = ~clk;

    task expect_eq(input integer got, input integer want, input [255:0] what);
        begin
            if (got !== want) begin
                $display("FAIL: %0s: %0d, erwartet %0d bei t=%0t", what, got, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    // ready darf erst nach dem letzten Register kommen.
    always @(posedge ready)
        if (n_writes % N_REGS != 0) begin
            $display("FAIL: ready nach %0d Schreibzugriffen bei t=%0t", n_writes, $time);
            errors = errors + 1;
        end

    initial begin
        $dumpfile("tb/build/tb_hdmi_config.vcd");
        $dumpvars(0, tb_hdmi_config);

        repeat (3) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        // 1. Wartezeit: Bus bleibt frei
        repeat (STARTUP_CLKS - 5) begin
            @(negedge clk);
            if (!(scl && sda)) begin
                $display("FAIL: Bus nicht frei waehrend der Wartezeit bei t=%0t", $time);
                errors = errors + 1;
            end
        end
        expect_eq(ready, 0, "ready waehrend der Wartezeit");

        // 2. vollständige Konfiguration
        wait (ready);
        @(negedge clk);
        expect_eq(n_writes, N_REGS, "Anzahl Schreibzugriffe");
        expect_eq(slave.mem[8'h41], 8'h10, "Register $41");
        expect_eq(slave.mem[8'hAF], 8'h16, "Register $AF");
        expect_eq(slave.mem[8'h15], 8'h20, "Register $15");
        expect_eq(last_reg, 8'hFA, "letztes Register");
        expect_eq(last_data, 8'h7D, "letzter Wert");
        expect_eq(nack, 0, "nack nach Erfolg");

        // 3. Baustein antwortet zunächst nicht
        force_nack = 1'b1;
        @(negedge clk) rst = 1'b1;
        @(negedge clk) rst = 1'b0;
        repeat (5000) @(posedge clk);
        expect_eq(ready, 0, "ready ohne Antwort");
        expect_eq(n_writes, N_REGS, "keine Schreibzugriffe ohne Antwort");
        expect_eq(nack, 1, "nack ohne Antwort");
        force_nack = 1'b0;
        wait (ready);
        @(negedge clk);
        expect_eq(n_writes, 2 * N_REGS, "Schreibzugriffe nach Wiederholung");
        expect_eq(nack, 0, "nack nach Wiederholung");

        // 4. Interrupt löst Neukonfiguration aus
        @(negedge clk) int_n = 1'b0;
        repeat (4) @(negedge clk);
        int_n = 1'b1;
        expect_eq(ready, 0, "ready nach Interrupt");
        wait (ready);
        @(negedge clk);
        expect_eq(n_writes, 3 * N_REGS, "Schreibzugriffe nach Interrupt");

        if (errors == 0) $display("PASS: tb_hdmi_config");
        else             $display("FAIL: tb_hdmi_config (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #30_000_000;
        $display("FAIL: tb_hdmi_config Timeout (ready=%b, Schreibzugriffe=%0d)", ready, n_writes);
        $finish;
    end

endmodule

`default_nettype wire
