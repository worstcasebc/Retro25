// SPDX-License-Identifier: GPL-3.0-or-later
// tb_hps_gp_bridge — Testbench für hps_gp_bridge.
//
// Nachgebildet wird die Gegenseite so, wie sie in MiSTers sys_top.v steht:
// gp_out über 2 FF in clk_sys, io_strobe = steigende Flanke von Bit 17,
// io_ack zwei Takte danach (eingefroren, solange io_wait), Kennung
// {24'h5CA623, 8'hA4} bei gp_out[31] = 0. Ein Antwortgeber wie hps_io merkt
// sich jedes Wort und antwortet mit Wort ^ 16'hA5A5.
// Abgespielt werden die Zugriffsmuster aus Main_MiSTer (fpga_io.cpp):
//   fpga_spi            Wort, Wort|Strobe, warten auf ACK, Wort, warten
//   fpga_spi_fast       Wort, Wort|Strobe, Wort, GPI lesen (ohne Warten)
//   fpga_spi_fast_block Wort|Strobe, Wort im Wechsel, ohne Warten
// Geprüft: kein Strobe geht verloren (langsamer und schneller clk_sys),
// Antworten stimmen, Kennung, Lesen/Schreiben GPO, ID, STATUS, Verhalten bei
// io_wait und bei stehendem clk_sys (kein Hängen, GPI = 0x8000_0000).

`timescale 1ns/1ps
`default_nettype none

module tb_hps_gp_bridge;

    localparam TIMEOUT = 200, ALIVE_WINDOW = 100;
    localparam [31:0] STROBE = 32'h0002_0000;
    localparam [31:0] UIO    = 32'h0010_0000;   // ss2: User-I/O ausgewählt
    localparam [31:0] NORMAL = 32'h8000_0000;   // Bit 31: Normalbetrieb

    // --- Takte -------------------------------------------------------------
    reg clk_av = 1'b0;
    always #5 clk_av = ~clk_av;                 // 100 MHz

    reg  clk_sys = 1'b0;
    reg  sys_run = 1'b1;
    real sys_half = 23.8;                       // 21 MHz
    always begin
        #(sys_half);
        if (sys_run) clk_sys = ~clk_sys;
    end

    // --- Prüfling ----------------------------------------------------------
    reg         rst_av = 1'b1;
    reg  [1:0]  address = 2'd0;
    reg         write = 1'b0;
    reg  [31:0] writedata = 32'd0;
    reg  [3:0]  byteenable = 4'hF;
    reg         read = 1'b0;
    wire [31:0] readdata;
    wire        readdatavalid;
    wire        waitrequest;
    wire [31:0] gp_out;
    wire [31:0] gp_in_mux;

    hps_gp_bridge #(.TIMEOUT(TIMEOUT), .ALIVE_WINDOW(ALIVE_WINDOW)) dut (
        .clk_av            (clk_av),
        .rst_av            (rst_av),
        .avs_address       (address),
        .avs_write         (write),
        .avs_writedata     (writedata),
        .avs_byteenable    (byteenable),
        .avs_read          (read),
        .avs_readdata      (readdata),
        .avs_readdatavalid (readdatavalid),
        .avs_waitrequest   (waitrequest),
        .clk_sys           (clk_sys),
        .gp_out            (gp_out),
        .gp_in             (gp_in_mux)
    );

    // --- Gegenseite wie in sys_top.v ----------------------------------------
    reg [31:0] gp_outd = 0, gp_outr = 0;
    always @(posedge clk_sys) begin
        gp_outd <= gp_out;
        gp_outr <= gp_outd;
    end

    wire [15:0] io_din = gp_outr[15:0];
    wire        io_clk = gp_outr[17];
    reg         io_wait = 1'b0;
    reg         rack = 1'b0, io_ack = 1'b0;
    wire        io_strobe = ~rack & io_clk;

    always @(posedge clk_sys)
        if (~io_wait | io_strobe) begin
            rack   <= io_clk;
            io_ack <= rack;
        end

    // Antwortgeber wie hps_io: Wort merken, Antwort im nächsten Takt.
    reg  [15:0] io_dout = 16'd0;
    reg  [15:0] rx [0:1023];
    integer     nrx = 0;

    always @(posedge clk_sys)
        if (io_strobe) begin
            rx[nrx] <= io_din;
            nrx     <= nrx + 1;
            io_dout <= io_din ^ 16'hA5A5;
        end

    wire [31:0] gp_in = {1'b0, 2'b00, 1'b0, 7'd0, 1'b1, 2'b01, io_ack, 1'b1, io_dout};
    assign gp_in_mux = ~gp_out[31] ? {24'h5CA623, 8'hA4} : gp_in;

    // --- Avalon-Master ------------------------------------------------------
    integer errors = 0;
    integer wait_cycles;

    task av_write(input [1:0] a, input [31:0] d);
        begin
            @(negedge clk_av);
            address = a; writedata = d; byteenable = 4'hF; write = 1'b1;
            #1;                                   // waitrequest neu berechnen lassen
            wait_cycles = 0;
            while (waitrequest) begin
                @(negedge clk_av);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > 10 * TIMEOUT) begin
                    $display("FAIL: Schreibzugriff hängt (Adresse %0d)", a);
                    errors = errors + 1;
                    disable av_write;
                end
            end
            @(posedge clk_av);
            #1 write = 1'b0;
        end
    endtask

    task av_read(input [1:0] a, output [31:0] d);
        begin
            @(negedge clk_av);
            address = a; read = 1'b1;
            @(posedge clk_av);                    // Zugriff angenommen, Daten
            #1;                                   // stehen mit dieser Flanke bereit
            read = 1'b0;
            if (!readdatavalid) begin
                $display("FAIL: readdatavalid fehlt");
                errors = errors + 1;
            end
            d = readdata;
        end
    endtask

    task expect(input [255:0] what, input [31:0] got, input [31:0] want);
        if (got !== want) begin
            $display("FAIL: %0s = %h, erwartet %h", what, got, want);
            errors = errors + 1;
        end
    endtask

    // fpga_spi aus Main_MiSTer: mit Warten auf ACK
    task spi(input [15:0] word, output [15:0] answer);
        reg [31:0] gpo, gpi;
        integer n;
        begin
            gpo = NORMAL | UIO | word;
            av_write(2'd0, gpo);
            av_write(2'd0, gpo | STROBE);
            n = 0;
            gpi = 0;
            while (!gpi[17] && n < 1000) begin av_read(2'd1, gpi); n = n + 1; end
            av_write(2'd0, gpo);
            while (gpi[17] && n < 2000) begin av_read(2'd1, gpi); n = n + 1; end
            if (n >= 1000) begin
                $display("FAIL: ACK-Handshake hängt bei Wort %h", word);
                errors = errors + 1;
            end
            answer = gpi[15:0];
        end
    endtask

    // fpga_spi_fast: ohne Warten
    task spi_fast(input [15:0] word, output [15:0] answer);
        reg [31:0] gpo, gpi;
        begin
            gpo = NORMAL | UIO | word;
            av_write(2'd0, gpo);
            av_write(2'd0, gpo | STROBE);
            av_write(2'd0, gpo);
            av_read(2'd1, gpi);
            answer = gpi[15:0];
        end
    endtask

    // fpga_spi_fast_block_write: Wort|Strobe und Wort im Wechsel
    task block_write(input integer count, input [15:0] seed);
        integer k, start;
        begin
            start = nrx;
            for (k = 0; k < count; k = k + 1) begin
                av_write(2'd0, NORMAL | UIO | (seed + k));
                av_write(2'd0, NORMAL | UIO | STROBE | (seed + k));
            end
            av_write(2'd0, NORMAL | UIO);
            repeat (20) @(posedge clk_sys);
            if (nrx - start != count) begin
                $display("FAIL: %0d Wörter gesendet, %0d angekommen (clk_sys-Halbperiode %0.1f ns)",
                         count, nrx - start, sys_half);
                errors = errors + 1;
            end
            for (k = 0; k < count && k < nrx - start; k = k + 1)
                if (rx[start + k] !== seed + k) begin
                    $display("FAIL: Wort %0d = %h, erwartet %h", k, rx[start + k], seed + k);
                    errors = errors + 1;
                    k = count;
                end
        end
    endtask

    reg [31:0] d;
    reg [15:0] ans;
    integer    k, t0;

    initial begin
        $dumpfile("tb/build/tb_hps_gp_bridge.vcd");
        $dumpvars(0, tb_hps_gp_bridge);

        repeat (5) @(posedge clk_av);
        rst_av = 1'b0;
        repeat (ALIVE_WINDOW / 4) @(posedge clk_av);

        // ID, STATUS, GPO lesen/schreiben
        av_read(2'd3, d);  expect("ID", d, 32'h5232_3547);
        av_read(2'd2, d);  expect("STATUS (clk_sys läuft)", d, 32'h1);
        av_write(2'd0, 32'h1234_5678);
        av_read(2'd0, d);  expect("GPO zurücklesen", d, 32'h1234_5678);
        @(negedge clk_av); byteenable = 4'b0001;
        address = 2'd0; writedata = 32'hFFFF_FFAB; write = 1'b1;
        #1;
        while (waitrequest) @(negedge clk_av);
        @(posedge clk_av); #1 write = 1'b0; byteenable = 4'hF;
        av_read(2'd0, d);  expect("GPO byteweise", d, 32'h1234_56AB);

        // Kennung bei gp_out[31] = 0, normale Daten bei 1
        av_write(2'd0, 32'h0000_0000);
        av_read(2'd1, d);  expect("Kennung", d, 32'h5CA6_23A4);
        av_write(2'd0, NORMAL);
        av_read(2'd1, d);  expect("io_ver in GPI[19:18]", {30'd0, d[19:18]}, 32'd1);

        // fpga_spi mit Handshake
        for (k = 0; k < 8; k = k + 1) begin
            spi(16'h1000 + k * 16'h0111, ans);
            expect("spi-Antwort", {16'd0, ans}, {16'd0, (16'h1000 + k * 16'h0111) ^ 16'hA5A5});
        end

        // fpga_spi_fast ohne Warten
        for (k = 0; k < 8; k = k + 1) begin
            spi_fast(16'h2000 + k, ans);
            expect("spi_fast-Antwort", {16'd0, ans}, {16'd0, (16'h2000 + k) ^ 16'hA5A5});
        end

        // Blockschreiben: langsamer clk_sys (21 MHz), dann schneller (150 MHz)
        block_write(256, 16'h4000);
        sys_half = 3.33;
        repeat (50) @(posedge clk_sys);
        block_write(256, 16'h8000);
        sys_half = 50.0;                          // 10 MHz
        repeat (50) @(posedge clk_sys);
        block_write(64, 16'hC000);
        sys_half = 23.8;
        repeat (50) @(posedge clk_sys);

        // io_wait: ACK friert ein, Schreibzugriffe dürfen trotzdem nicht hängen
        io_wait = 1'b1;
        av_write(2'd0, NORMAL | UIO | 16'h0055);
        av_write(2'd0, NORMAL | UIO | STROBE | 16'h0055);
        av_write(2'd0, NORMAL | UIO | 16'h0055);
        av_read(2'd2, d);  expect("STATUS nach io_wait (kein Timeout)", d, 32'h1);
        io_wait = 1'b0;
        repeat (10) @(posedge clk_sys);

        // clk_sys steht: GPI meldet „nicht bereit“, Schreiben hängt nicht
        sys_run = 1'b0;
        repeat (ALIVE_WINDOW + 20) @(posedge clk_av);
        av_read(2'd1, d);  expect("GPI bei stehendem clk_sys", d, 32'h8000_0000);
        av_read(2'd2, d);  expect("STATUS bei stehendem clk_sys", d, 32'h0);
        t0 = $time;
        av_write(2'd0, NORMAL | 16'h0077);
        if ($time - t0 > 100) begin
            $display("FAIL: Schreiben bei stehendem clk_sys dauert %0d ns", $time - t0);
            errors = errors + 1;
        end
        av_read(2'd0, d);  expect("GPO bei stehendem clk_sys", d, NORMAL | 32'h0077);

        // clk_sys bleibt mitten im Handshake stehen: Zugriff endet, Merker gesetzt
        sys_run = 1'b1;
        repeat (ALIVE_WINDOW) @(posedge clk_av);
        av_read(2'd2, d);  expect("STATUS wieder laufend", d, 32'h1);
        fork
            av_write(2'd0, NORMAL | 16'h0099);
            begin @(posedge clk_av); sys_run = 1'b0; end
        join
        av_read(2'd2, d);  expect("STATUS Timeout-Merker", d, 32'h2);
        sys_run = 1'b1;
        repeat (ALIVE_WINDOW) @(posedge clk_av);
        av_write(2'd2, 32'h2);                    // Merker löschen
        av_read(2'd2, d);  expect("STATUS nach Löschen", d, 32'h1);

        // Nach dem Stillstand geht der Handshake wieder
        spi(16'h0BAD, ans);
        expect("spi nach Stillstand", {16'd0, ans}, {16'd0, 16'h0BAD ^ 16'hA5A5});

        if (errors == 0) $display("PASS: tb_hps_gp_bridge");
        else             $display("FAIL: tb_hps_gp_bridge, %0d Fehler", errors);
        $finish;
    end

endmodule

`default_nettype wire
