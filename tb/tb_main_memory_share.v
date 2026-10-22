// SPDX-License-Identifier: GPL-3.0-or-later
// Simulator: Questa
// Dateien: cores/z486/pro/src/memory/main_memory.sv
//
// tb_main_memory_share — z486 main_memory mit dem Briefkasten des gemeinsamen
// Ordners (Retro25, make_pro.py): CPU-Zugriffe auf 0xCE000-0xCFFFF gehen über
// den DDR-Port an 0x300CE000, nicht ins SDRAM.
//   1. Dword/Wort/Byte schreiben -> DDR-Adresse, Byte-Enables, Datenspur
//   2. Zurücklesen (untere/obere Hälfte des 64-bit-Worts)
//   3. Ränder: CDFFC und D0000 gehen ins SDRAM, CFFFC in den Briefkasten
//   4. Befehls-Zeilenfüllung (Burst) im Briefkasten -> FFFFFFFF, kein DDR
//   5. Linearer Framebuffer (0x0F800000) unverändert an 0x3F800000
//   6. Lesepuffer für den Framebuffer: Treffer ohne DDR, Byte-Schreiben wird
//      nachgeführt, nächstes Wort liest wieder DDR
//   7. Briefkasten nie gepuffert (Main schreibt dort von außen)
// DDR-Modell mit zufälligem busy und 2..7 Takten Leselatenz.

`timescale 1ns/1ps

module tb_main_memory_share;

reg clk = 0;
always #5 clk = ~clk;
reg reset = 1;

// ---------------------------------------------------------------- CPU-Seite
reg  [31:0] cpu_addr = 0;
reg  [31:0] cpu_din = 0;
wire [31:0] cpu_dout;
wire        cpu_resp_valid;
wire [127:0] cpu_line_dout;
wire        cpu_line_resp_valid;
reg  [3:0]  cpu_be = 4'hF;
reg  [7:0]  cpu_burstcount = 8'd1;
reg         cpu_line_read = 0;
wire        cpu_ready;
reg         cpu_valid = 0;
reg         cpu_write = 0;

// ---------------------------------------------------------------- SDRAM-Seite
wire [31:0] mem_addr, mem_din;
wire [3:0]  mem_be;
wire [7:0]  mem_burstcount;
wire        mem_line_read, mem_valid, mem_write;
reg  [31:0] mem_dout = 0;
reg         mem_resp_valid = 0;
wire        mem_ready = mem_valid;          // nimmt sofort an
integer     sdram_reqs = 0;
always @(posedge clk) begin
    mem_resp_valid <= 0;
    if (mem_valid) begin
        sdram_reqs <= sdram_reqs + 1;
        if (!mem_write) begin
            mem_resp_valid <= 1;
            mem_dout <= 32'h5D00_0000 ^ mem_addr;   // erkennbares Muster
        end
    end
end

// ---------------------------------------------------------------- DDR-Modell
wire [28:0] fb_ddram_addr;
wire [63:0] fb_ddram_din;
wire [7:0]  fb_ddram_be;
wire        fb_ddram_we, fb_ddram_rd;
wire [7:0]  fb_ddram_burstcnt;
reg  [63:0] fb_ddram_dout = 0;
reg         fb_ddram_dout_ready = 0;
reg         fb_ddram_busy = 0;

reg  [63:0] ddr [0:1023];                   // Wort i = Adresse BASE + i
localparam [28:0] SHARE_W = 32'h300CE000 >> 3;
localparam [28:0] LFB_W   = 32'h3F800000 >> 3;
reg  [28:0] last_addr;
reg  [7:0]  last_be;
integer     ddr_writes = 0, ddr_reads = 0, rd_wait = -1;

function automatic integer idx(input [28:0] a);
    idx = (a >= LFB_W) ? 512 + (a - LFB_W) : (a - SHARE_W);
endfunction

integer seed = 7;
always @(posedge clk) begin
    fb_ddram_dout_ready <= 0;
    if (!reset) fb_ddram_busy <= ($random(seed) & 3) == 0;    // ~25 % busy
    if (fb_ddram_we && !fb_ddram_busy) begin
        for (int b = 0; b < 8; b++)
            if (fb_ddram_be[b]) ddr[idx(fb_ddram_addr)][b*8 +: 8] <= fb_ddram_din[b*8 +: 8];
        last_addr <= fb_ddram_addr;
        last_be <= fb_ddram_be;
        ddr_writes <= ddr_writes + 1;
        if (fb_ddram_burstcnt != 1) $display("FAIL: Schreib-Burst %0d", fb_ddram_burstcnt);
    end
    if (fb_ddram_rd && !fb_ddram_busy) begin
        if (rd_wait >= 0) $display("FAIL: zweite Leseanfrage vor der Antwort");
        last_addr <= fb_ddram_addr;
        rd_wait <= 2 + ($random(seed) & 5);
        ddr_reads <= ddr_reads + 1;
    end
    if (rd_wait == 0) begin
        fb_ddram_dout <= ddr[idx(last_addr)];
        fb_ddram_dout_ready <= 1;
    end
    if (rd_wait >= 0) rd_wait <= rd_wait - 1;
end

// ---------------------------------------------------------------- DUT
main_memory dut (
    .clk(clk), .reset(reset),
    .cpu_addr(cpu_addr), .cpu_din(cpu_din), .cpu_dout(cpu_dout),
    .cpu_resp_valid(cpu_resp_valid), .cpu_line_dout(cpu_line_dout),
    .cpu_line_resp_valid(cpu_line_resp_valid), .cpu_be(cpu_be),
    .cpu_burstcount(cpu_burstcount), .cpu_line_read(cpu_line_read),
    .cpu_ready(cpu_ready), .cpu_valid(cpu_valid), .cpu_write(cpu_write),
    .ram_size(2'd3),
    .mem_addr(mem_addr), .mem_din(mem_din), .mem_dout(mem_dout),
    .mem_resp_valid(mem_resp_valid), .mem_line_dout(128'd0),
    .mem_line_resp_valid(1'b0), .mem_be(mem_be), .mem_burstcount(mem_burstcount),
    .mem_line_read(mem_line_read), .mem_ready(mem_ready), .mem_valid(mem_valid),
    .mem_write(mem_write),
    .vga_address(), .vga_readdata(8'h00), .vga_writedata(), .vga_memmode(3'b100),
    .vga_read(), .vga_write(), .vga_write_dword(), .vga_writedata_dword(),
    .vga_dword_write_ok(1'b0), .vga_wr_seg(6'd0), .vga_rd_seg(6'd0),
    .vga_fb_en(1'b0), .vga_chain4(1'b0), .vga_map_mask(4'hF), .vga_read_plane(2'd0),
    .vga_write_mode(2'd0), .vga_wr_done(),
    .fb_ddram_addr(fb_ddram_addr), .fb_ddram_din(fb_ddram_din), .fb_ddram_be(fb_ddram_be),
    .fb_ddram_we(fb_ddram_we), .fb_ddram_rd(fb_ddram_rd), .fb_ddram_dout(fb_ddram_dout),
    .fb_ddram_dout_ready(fb_ddram_dout_ready), .fb_ddram_burstcnt(fb_ddram_burstcnt),
    .fb_ddram_busy(fb_ddram_busy)
);

// ---------------------------------------------------------------- Hilfen
integer errors = 0;
reg [31:0] rd_data;
integer resp_cnt;

// Ein Zugriff wie der Bus des z486: valid halten bis ready, dann bei Lesen
// auf resp_valid warten (burst Antworten).
task automatic access(input [31:0] a, input wr, input [3:0] be, input [31:0] d,
                      input [7:0] burst);
    integer t;
    @(negedge clk);
    cpu_addr = a; cpu_write = wr; cpu_be = be; cpu_din = d; cpu_burstcount = burst;
    cpu_valid = 1;
    #1;   // kombinatorisches ready (SDRAM-Weg) erst auswerten lassen
    t = 0;
    while (!cpu_ready) begin @(posedge clk); #1; t++;
        if (t > 200) begin $display("FAIL: kein ready für %h", a); errors++; disable access; end
    end
    @(posedge clk); #1;
    cpu_valid = 0;
    if (!wr) begin
        resp_cnt = 0;
        t = 0;
        while (resp_cnt < burst) begin
            if (cpu_resp_valid) begin rd_data = cpu_dout; resp_cnt++; end
            if (resp_cnt < burst) begin @(posedge clk); #1; end
            if (++t > 200) begin $display("FAIL: keine Antwort für %h", a); errors++; disable access; end
        end
    end
    // warten, bis die Zustandsmaschine wieder frei ist
    repeat (12) @(posedge clk);
endtask

task automatic check(input [255:0] what, input [63:0] got, input [63:0] exp);
    if (got !== exp) begin
        $display("FAIL: %0s: %h statt %h", what, got, exp);
        errors++;
    end
endtask

integer s0, d0;
initial begin
    for (int i = 0; i < 1024; i++) ddr[i] = 64'h0;
    repeat (4) @(posedge clk);
    reset = 0;
    repeat (4) @(posedge clk);

    // 1. Schreiben in den Briefkasten
    s0 = sdram_reqs; d0 = ddr_writes;
    access(32'h000CE000, 1, 4'hF, 32'h11223344, 1);
    check("Adresse CE000", last_addr, SHARE_W);
    check("BE CE000", last_be, 8'h0F);
    access(32'h000CE004, 1, 4'hF, 32'h55667788, 1);
    check("BE CE004", last_be, 8'hF0);
    check("DDR-Wort 0", ddr[0], 64'h55667788_11223344);
    access(32'h000CE000, 1, 4'b1100, 32'hAAAA0000, 1);          // Wort bei CE002
    check("BE Wort CE002", last_be, 8'h0C);
    access(32'h000CE004, 1, 4'b0010, 32'h0000BB00, 1);          // Byte bei CE005
    check("DDR-Wort 0 nach Wort/Byte", ddr[0], 64'h5566BB88_AAAA3344);
    access(32'h000CFFFC, 1, 4'hF, 32'hCAFEF00D, 1);
    check("Adresse CFFFC", last_addr, SHARE_W + 29'h3FF);
    check("BE CFFFC", last_be, 8'hF0);
    check("SDRAM unberührt beim Schreiben", sdram_reqs - s0, 0);
    check("DDR-Schreibzugriffe", ddr_writes - d0, 5);

    // 2. Zurücklesen
    s0 = sdram_reqs;
    access(32'h000CE000, 0, 4'hF, 0, 1);
    check("lesen CE000", rd_data, 32'hAAAA3344);
    access(32'h000CE004, 0, 4'hF, 0, 1);
    check("lesen CE004", rd_data, 32'h5566BB88);
    access(32'h000CFFFC, 0, 4'hF, 0, 1);
    check("lesen CFFFC", rd_data, 32'hCAFEF00D);
    check("SDRAM unberührt beim Lesen", sdram_reqs - s0, 0);

    // 3. Ränder: knapp davor/dahinter ins SDRAM
    s0 = sdram_reqs; d0 = ddr_reads;
    access(32'h000CDFFC, 0, 4'hF, 0, 1);
    check("lesen CDFFC (SDRAM)", rd_data, 32'h5D00_0000 ^ 32'h000CDFFC);
    access(32'h000D0000, 0, 4'hF, 0, 1);
    check("lesen D0000 (SDRAM)", rd_data, 32'h5D00_0000 ^ 32'h000D0000);
    access(32'h000D0000, 1, 4'hF, 32'h12345678, 1);
    check("SDRAM-Zugriffe an den Rändern", sdram_reqs - s0, 3);
    check("kein DDR an den Rändern", ddr_reads - d0, 0);

    // 4. Zeilenfüllung (Befehlscache) im Briefkasten
    d0 = ddr_reads; s0 = sdram_reqs;
    access(32'h000CE000, 0, 4'hF, 0, 4);
    check("Burst-Antworten", resp_cnt, 4);
    check("Burst-Daten", rd_data, 32'hFFFFFFFF);
    check("Burst ohne DDR", ddr_reads - d0, 0);
    check("Burst ohne SDRAM", sdram_reqs - s0, 0);

    // 5. Linearer Framebuffer unverändert
    access(32'h0F800010, 1, 4'hF, 32'hDEADBEEF, 1);
    check("Adresse LFB", last_addr, LFB_W + 29'd2);
    check("BE LFB", last_be, 8'h0F);
    access(32'h0F800010, 0, 4'hF, 0, 1);
    check("lesen LFB", rd_data, 32'hDEADBEEF);

    // 6. Lesepuffer (LFB): Treffer ohne DDR, Schreiben wird nachgeführt
    access(32'h0F800020, 1, 4'hF, 32'hAABBCCDD, 1);
    d0 = ddr_reads;
    access(32'h0F800020, 0, 4'hF, 0, 1);
    check("LFB lesen (Fehlzugriff)", rd_data, 32'hAABBCCDD);
    check("Fehlzugriff liest DDR", ddr_reads - d0, 1);
    access(32'h0F800024, 0, 4'hF, 0, 1);
    check("LFB obere Hälfte (Treffer)", rd_data, 32'h00000000);
    access(32'h0F800020, 1, 4'b0010, 32'h00005500, 1);      // Byte 0F800021
    access(32'h0F800020, 0, 4'hF, 0, 1);
    check("Treffer nach Byte-Schreiben", rd_data, 32'hAABB55DD);
    check("Treffer ohne DDR", ddr_reads - d0, 1);
    check("DDR nach Byte-Schreiben", ddr[512 + 4], 64'h00000000_AABB55DD);
    access(32'h0F800028, 0, 4'hF, 0, 1);
    check("nächstes Wort liest DDR", ddr_reads - d0, 2);

    // 7. Briefkasten nie gepuffert: "Main" ändert das DDR dazwischen
    d0 = ddr_reads;
    access(32'h000CE040, 0, 4'hF, 0, 1);
    ddr[8] = 64'h0000_0000_1234_5678;
    access(32'h000CE040, 0, 4'hF, 0, 1);
    check("Briefkasten sieht Mains Wert", rd_data, 32'h12345678);
    check("Briefkasten liest jedes Mal DDR", ddr_reads - d0, 2);

    if (errors == 0) $display("PASS: tb_main_memory_share");
    else $display("FAIL: %0d Fehler", errors);
    $finish;
end

initial begin
    #200000;
    $display("FAIL: Zeitüberschreitung");
    $finish;
end

endmodule
