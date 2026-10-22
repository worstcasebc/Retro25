// SPDX-License-Identifier: GPL-3.0-or-later
// tb_p0_regs — Testbench für p0_regs.
//
// Prüft: ID lesen, SCRATCH ganz und byteweise schreiben und zurücklesen,
// UPTIME zählt hoch, STATUS gibt den Eingang wieder, readdatavalid kommt
// genau einen Takt nach read, waitrequest bleibt 0, Reset löscht SCRATCH.

`timescale 1ns/1ps
`default_nettype none

module tb_p0_regs;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [1:0]  address = 2'd0;
    reg         write = 1'b0;
    reg  [31:0] writedata = 32'd0;
    reg  [3:0]  byteenable = 4'hF;
    reg         read = 1'b0;
    wire [31:0] readdata;
    wire        readdatavalid;
    wire        waitrequest;
    reg  [31:0] status = 32'hCAFE_0001;

    integer errors = 0;

    always #5 clk = ~clk;   // 100 MHz

    p0_regs #(.ID(32'h5232_3542)) dut (
        .clk               (clk),
        .rst               (rst),
        .avs_address       (address),
        .avs_write         (write),
        .avs_writedata     (writedata),
        .avs_byteenable    (byteenable),
        .avs_read          (read),
        .avs_readdata      (readdata),
        .avs_readdatavalid (readdatavalid),
        .avs_waitrequest   (waitrequest),
        .status            (status)
    );

    task wr(input [1:0] a, input [31:0] d, input [3:0] be);
        begin
            @(negedge clk);
            address = a; writedata = d; byteenable = be; write = 1'b1;
            @(negedge clk);
            write = 1'b0; byteenable = 4'hF;
        end
    endtask

    task rd(input [1:0] a, output [31:0] d);
        begin
            @(negedge clk);
            address = a; read = 1'b1;
            @(negedge clk);
            read = 1'b0;
            if (!readdatavalid) begin
                $display("FAIL: readdatavalid nicht einen Takt nach read (Adresse %0d)", a);
                errors = errors + 1;
            end
            d = readdata;
            @(negedge clk);
            if (readdatavalid) begin
                $display("FAIL: readdatavalid länger als einen Takt");
                errors = errors + 1;
            end
        end
    endtask

    task expect(input [255:0] what, input [31:0] got, input [31:0] want);
        begin
            if (got !== want) begin
                $display("FAIL: %0s = %h, erwartet %h", what, got, want);
                errors = errors + 1;
            end
        end
    endtask

    reg [31:0] d, d2;

    always @(posedge clk)
        if (!rst && waitrequest !== 1'b0) begin
            $display("FAIL: waitrequest = %b", waitrequest);
            errors = errors + 1;
        end

    initial begin
        $dumpfile("tb/build/tb_p0_regs.vcd");
        $dumpvars(0, tb_p0_regs);

        repeat (3) @(posedge clk);
        rst = 1'b0;

        rd(2'd0, d);  expect("ID", d, 32'h5232_3542);
        rd(2'd1, d);  expect("SCRATCH nach Reset", d, 32'd0);

        wr(2'd1, 32'h1234_5678, 4'hF);
        rd(2'd1, d);  expect("SCRATCH", d, 32'h1234_5678);

        wr(2'd1, 32'hAABB_CCDD, 4'b0101);     // nur Byte 0 und 2
        rd(2'd1, d);  expect("SCRATCH byteweise", d, 32'h12BB_56DD);

        wr(2'd0, 32'hFFFF_FFFF, 4'hF);         // ID ist nur lesbar
        rd(2'd0, d);  expect("ID nach Schreibversuch", d, 32'h5232_3542);

        rd(2'd2, d);
        repeat (10) @(posedge clk);
        rd(2'd2, d2);
        if (d2 - d < 10) begin
            $display("FAIL: UPTIME zählt nicht (%0d -> %0d)", d, d2);
            errors = errors + 1;
        end

        rd(2'd3, d);  expect("STATUS", d, 32'hCAFE_0001);
        status = 32'h0000_00A5;
        rd(2'd3, d);  expect("STATUS neu", d, 32'h0000_00A5);

        @(negedge clk) rst = 1'b1;
        @(negedge clk) rst = 1'b0;
        rd(2'd1, d);  expect("SCRATCH nach zweitem Reset", d, 32'd0);

        if (errors == 0) $display("PASS: tb_p0_regs");
        else             $display("FAIL: tb_p0_regs, %0d Fehler", errors);
        $finish;
    end

endmodule

`default_nettype wire
