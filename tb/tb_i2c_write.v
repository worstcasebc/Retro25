// SPDX-License-Identifier: GPL-3.0-or-later
// Übernommen aus C64-DE25 (gleicher Autor).
// tb_i2c_write — selbstprüfende Testbench für i2c_write.
//
// Am Bus hängt das Modell i2c_slave_model (Adresse $72).
// 1. Ein Schreibzugriff kommt an: richtiges Register, richtiger Wert, kein
//    ACK-Fehler; busy ist währenddessen 1.
// 2. Der SCL-Takt dauert 4 * CLKS_PER_QUARTER Takte.
// 3. Zugriff auf eine fremde Adresse: ACK-Fehler, nichts wird geschrieben.
// 4. Danach funktioniert ein normaler Zugriff wieder (Fehler ist gelöscht).
// 5. SDA ändert sich während der Übertragung nur, wenn SCL 0 ist
//    (ausgenommen Start und Stopp).

`timescale 1ns / 1ps
`default_nettype none

module tb_i2c_write;

    localparam CLKS_PER_QUARTER = 4;

    reg        clk      = 1'b0;
    reg        rst      = 1'b1;
    reg        start    = 1'b0;
    reg  [7:0] dev_addr = 8'h00;
    reg  [7:0] reg_addr = 8'h00;
    reg  [7:0] data     = 8'h00;
    wire       busy;
    wire       done;
    wire       ack_error;
    wire       scl_oe;
    wire       sda_oe;
    wire       slave_sda_low;
    wire [31:0] n_writes;
    wire [7:0]  last_reg;
    wire [7:0]  last_data;

    // Der Bus mit Pull-up: 1, solange niemand zieht.
    wire scl = ~scl_oe;
    wire sda = ~(sda_oe | slave_sda_low);

    integer errors = 0;

    i2c_write #(.CLKS_PER_QUARTER(CLKS_PER_QUARTER)) dut (
        .clk         (clk),
        .rst         (rst),
        .start       (start),
        .dev_addr    (dev_addr),
        .reg_addr    (reg_addr),
        .data        (data),
        .busy        (busy),
        .done_q      (done),
        .ack_error_q (ack_error),
        .scl_oe_q    (scl_oe),
        .sda_oe_q    (sda_oe),
        .sda_in      (sda)
    );

    i2c_slave_model slave (
        .scl        (scl),
        .sda        (sda),
        .force_nack (1'b0),
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

    // Startet einen Zugriff und wartet auf done.
    task write_reg(input [7:0] dev, input [7:0] register, input [7:0] value);
        begin
            @(negedge clk);
            dev_addr = dev; reg_addr = register; data = value;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            expect_eq(busy, 1, "busy nach start");
            @(posedge done);
            @(negedge clk);
        end
    endtask

    // 2. SCL-Periode messen (nur innerhalb eines Zugriffs, nicht dazwischen)
    time scl_rise = 0;
    always @(posedge scl) begin
        if (scl_rise != 0)
            expect_eq($time - scl_rise, 4 * CLKS_PER_QUARTER * 20, "SCL-Periode in ns");
        scl_rise = $time;
    end
    always @(posedge done) scl_rise = 0;

    // 5. Datenbits dürfen sich nur bei SCL = 0 ändern. Start und Stopp sind
    //    die beiden erlaubten Ausnahmen: genau je eine pro Zugriff.
    integer sda_changes_scl_high = 0;
    always @(sda) if (scl && !rst) sda_changes_scl_high = sda_changes_scl_high + 1;

    initial begin
        $dumpfile("tb/build/tb_i2c_write.vcd");
        $dumpvars(0, tb_i2c_write);

        repeat (3) @(posedge clk);
        @(negedge clk) rst = 1'b0;
        expect_eq(busy, 0, "busy nach Reset");
        expect_eq(scl, 1, "SCL frei nach Reset");
        expect_eq(sda, 1, "SDA frei nach Reset");

        // 1. normaler Zugriff
        write_reg(8'h72, 8'h98, 8'h03);
        expect_eq(ack_error, 0, "ACK-Fehler bei gueltigem Zugriff");
        expect_eq(n_writes, 1, "Anzahl Schreibzugriffe");
        expect_eq(last_reg, 8'h98, "Registeradresse");
        expect_eq(last_data, 8'h03, "Datenbyte");
        expect_eq(busy, 0, "busy nach done");
        expect_eq(scl & sda, 1, "Bus frei nach Stopp");

        // 3. fremde Adresse
        write_reg(8'h70, 8'h41, 8'h10);
        expect_eq(ack_error, 1, "ACK-Fehler bei fremder Adresse");
        expect_eq(n_writes, 1, "nichts geschrieben bei fremder Adresse");

        // 4. danach wieder normal, mit anderem Bitmuster
        write_reg(8'h72, 8'hA5, 8'h5A);
        expect_eq(ack_error, 0, "ACK-Fehler geloescht");
        expect_eq(n_writes, 2, "Anzahl Schreibzugriffe");
        expect_eq(last_reg, 8'hA5, "Registeradresse 2");
        expect_eq(last_data, 8'h5A, "Datenbyte 2");

        // 5. drei Zugriffe = drei Starts + drei Stopps
        expect_eq(sda_changes_scl_high, 6, "SDA-Wechsel bei SCL=1");

        if (errors == 0) $display("PASS: tb_i2c_write");
        else             $display("FAIL: tb_i2c_write (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #1_000_000;
        $display("FAIL: tb_i2c_write Timeout");
        $finish;
    end

endmodule

`default_nettype wire
