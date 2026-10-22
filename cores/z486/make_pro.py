# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt die Quartus-Pro/Agilex-5-Anpassungen des z486 aus vendor/.

Aufruf (aus dem Projektverzeichnis Retro25):
    python cores/z486/make_pro.py

Jede Anpassung ist eine Textersetzung in einer Kopie unter pro/ (gleicher
relativer Pfad wie unter vendor/), daneben die .patch-Datei zum Nachlesen.
vendor/ bleibt unverändert. Zusätzlich entsteht das Probeprojekt
probe/z486.qpf (Z2) mit den Revisionen z486_cpu (nur die CPU) und z486_sys
(PC ohne MiSTer-Rahmen); beide verwenden die pro/-Kopien statt der Originale.
"""
import difflib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
VENDOR = HERE / "vendor"
PRO = HERE / "pro"

# Z7 Lesepuffer (main_memory, siehe unten): FB_READ_WAIT nimmt die Daten aus
# rd64 (Puffer oder DDR), füllt den Puffer bei DDR-Daten und beendet auch bei
# einem Treffer (rb_hit_r) ohne DDR-Antwort. Der Block wird zur Laufzeit aus
# vendor/ gelesen (z486_MiSTer hat keine Lizenz — kein Fremdcode im Repo).
def fb_read_wait_patch() -> tuple:
    f = VENDOR / "src" / "memory" / "main_memory.sv"
    if not f.exists():
        return ("FB_READ_WAIT (vendor fehlt)", "")
    src = f.read_bytes().decode("utf-8").replace("\r\n", "\n")
    start = src.index("            FB_READ_WAIT:\n")
    tail = "                    vga_dout_ready <= 1;\n"
    end = src.index(tail, start) + len(tail)
    old = src[start:end]
    new = (old
        .replace("                if (fb_ddram_dout_ready) begin\n",
                 "                if (rb_hit_r || fb_ddram_dout_ready) begin   // Retro25: Lesepuffer\n")
        .replace("fb_ddram_dout[", "rd64[")
        .replace(tail,
                 "                    if (!rb_hit_r && fb_cacheable) begin   // Retro25: Puffer füllen\n"
                 "                        rb_valid <= 1;\n"
                 "                        rb_addr  <= fb_ddram_addr;\n"
                 "                        rb_data  <= fb_ddram_dout;\n"
                 "                    end\n"
                 "                    rb_hit_r <= 0;\n" + tail))
    return (old, new)


FB_READ_WAIT_OLD, FB_READ_WAIT_NEW = fb_read_wait_patch()

# Pfad unter vendor/ -> Liste (alt, neu, Grund[, "erstes"]). "alt" muss genau
# einmal vorkommen; mit "erstes" wird nur das erste von mehreren ersetzt.
# Zeilenenden: mit \n schreiben; bei CRLF-Dateien wird automatisch angepasst.
PATCHES = {
    "src/z486/ucode_rom.sv": [
        # Das altsyncram nutzt clock1 nur für einen eigenen Clock-Enable von
        # Port B; Agilex 5 erlaubt clock1 bei BIDIR_DUAL_PORT nicht (272006).
        # Der herstellerneutrale Zweig ist taktgleich und wird auf M20K abgebildet.
        ("`ifdef Z486_USE_ALTERA_UCODE_ROM\r\n", "`ifdef Z486_USE_ALTERA_UCODE_ROM_CYCLONE_V   // Retro25: aus\r\n",
         "clock1 bei BIDIR_DUAL_PORT auf Agilex 5 verboten -> inferiertes ROM"),
    ],
    "src/z486/z486_platform.svh": [
        # Agilex 5 kennt nur ramstyle M20K/MLAB/AUTO (272006). Die Kopie wird
        # als erste Datei übersetzt; ihr Include-Guard macht spätere
        # `include des Originals (neben den vendor-Quellen) wirkungslos.
        ('(* ramstyle = "M10K" *)', '(* ramstyle = "M20K" *)', "M10K gibt es nicht"),
        ('(* ramstyle = "M10K, no_rw_check" *)', '(* ramstyle = "M20K, no_rw_check" *)', "M10K gibt es nicht"),
    ],
    "src/z486/data_access.sv": [
        # Quartus Pro: bei `default_nettype none brauchen Eingangsports einen
        # ausdrücklichen Netztyp ("input wire logic"), sonst Fehler 17440.
        ("`default_nettype none\r\n", "", "default_nettype none + input logic -> Fehler 17440"),
        ("`default_nettype wire\r\n", "", "Gegenstück am Dateiende"),
    ],
    # Z7 x87: die FPU-Speicher sind für Cyclone V als altsyncram mit M10K
    # geschrieben (272006). ROMs: nur Blocktyp und Familie anpassen, Inhalt
    # weiter aus den .mif (SEARCH_PATH vendor/src/z486/x87).
    "src/z486/x87/x87_ucode_rom.sv": [
        ('.ram_block_type("M10K")', '.ram_block_type("M20K")', "M10K gibt es nicht"),
        ('.intended_device_family("Cyclone V")', '.intended_device_family("Agilex 5")', "Familie"),
    ],
    "src/z486/x87/x87_command_rom.sv": [
        ('.ram_block_type("M10K")', '.ram_block_type("M20K")', "M10K gibt es nicht"),
        ('.intended_device_family("Cyclone V")', '.intended_device_family("Agilex 5")', "Familie"),
    ],
    "src/z486/x87/x87_logexp_rom.sv": [
        ('.ram_block_type("M10K")', '.ram_block_type("M20K")', "M10K gibt es nicht"),
        ('.intended_device_family("Cyclone V")', '.intended_device_family("Agilex 5")', "Familie"),
    ],
    # Stapel 8 x 80 bit mit zwei Schreibports: altsyncram BIDIR_DUAL_PORT mit
    # read_during_write_mode_mixed_ports OLD_DATA gibt es auf Agilex 5 nicht.
    # Der herstellerneutrale Zweig (Register, 640 FF) liefert am anderen Port
    # ebenfalls den alten Wert.
    "src/z486/x87/x87_stack_mem.sv": [
        ("`ifdef Z486_USE_ALTERA_MEMORY\n", "`ifdef Z486_USE_ALTERA_MEMORY_CYCLONE_V   // Retro25: aus\n",
         "BIDIR + OLD_DATA auf Agilex 5 verboten -> Register"),
    ],
    "src/common/dpram.v": [
        # dpram_difclk: altsyncram BIDIR_DUAL_PORT mit clock1 (272006, wie
        # ucode_rom). Im MiSTer-Build ist clk_vga = clk_sys (z486_mister.sv);
        # der herstellerneutrale Zweig (auch der der Verilator-Simulation)
        # wird von Quartus als RAM mit einem Takt inferiert.
        ("`elsif ALTERA_RESERVED_QIS", "`elsif ALTERA_RESERVED_QIS_CYCLONE_V   // Retro25: aus",
         "clock1 bei BIDIR_DUAL_PORT auf Agilex 5 verboten -> inferiertes RAM"),
        # dpram (IDE-Sektorpuffer, 4K x 16): Lese-/Schreibverhalten auf
        # derselben Adresse wird im True-Dual-Port-M20K von Agilex 5 nicht
        # unterstützt (276009) -> Speicher in Logik, je ~110k ALMs. Main
        # (Port A) und CPU (Port B) greifen nacheinander zu -> egal.
        # (Die Zeile steht gleich auch in dpram_be -> nur das erste Vorkommen.)
        ("    reg [DATW-1:0] mem [0:MEMD-1]; // memory array",
         "    (* ramstyle = \"no_rw_check\" *) reg [DATW-1:0] mem [0:MEMD-1]; // memory array",
         "read-during-write -> no_rw_check", "erstes"),
        # dpram_difclk, inferierter Zweig (VGA-Planes 64K x 8, Palette, DAC):
        # "Adresse B registrieren + asynchron lesen" erkennt Quartus auf
        # Agilex 5 nicht als True-Dual-Port und legt das RAM je Leseport
        # doppelt an (VGA: 4,2 statt 2,1 Mbit). Synchrones Lesen mit Enable
        # ist taktgleich (Daten einen Takt nach der Adresse); nur zeigt eine
        # gehaltene Adresse spätere Schreibzugriffe nicht mehr — für die
        # Bildausgabe egal. Dazu no_rw_check wie bei dpram.
        ("    reg [ADRW-1:0] address_b_r;\n    assign q_a = q_a_r;\n    assign q_b = mem[address_b_r];\n\n"
         "    reg [DATW-1:0] mem [0:MEMD-1]; // memory array\n",
         "    reg [DATW-1:0] q_b_r;\n    assign q_a = q_a_r;\n    assign q_b = q_b_r;\n\n"
         "    (* ramstyle = \"no_rw_check\" *) reg [DATW-1:0] mem [0:MEMD-1]; // memory array\n",
         "Port B synchron lesen -> True-Dual-Port statt doppeltem RAM"),
        ("        if (enable_b_i)\n            address_b_r <= address_b;\n",
         "        if (enable_b_i)\n            q_b_r <= mem[address_b];\n",
         "Port B synchron lesen"),
    ],
    "src/memory/sdram.v": [
        # req_id_buf wird (resp_valid*/burst_done*) vor der Deklaration benutzt:
        # Quartus Pro legt dann ein implizites Netz ohne Treiber an (16746/
        # 16788), Questa bricht ab (vlog-2730). Deklaration nach vorn.
        ("reg busy_buf = 1'b1;\n", "reg busy_buf = 1'b1;\nreg [1:0]  req_id_buf;   // Retro25: vor die erste Verwendung\n",
         "req_id_buf vor der ersten Verwendung deklarieren"),
        ("reg [1:0]  req_id_buf;\nreg        req_large_buf;", "reg        req_large_buf;",
         "alte Deklaration entfernen"),
        # dq_out und dq_oen sitzen als I/O-Register im Pin und teilen sich dort
        # ein Clock-Enable; upstream lädt beide nur in einzelnen Zuständen
        # (eigenes Enable) -> Fitter-Fehler 14996/24403 (wie Memtest/C64, P4).
        # Stattdessen jeden Takt aus einer Formel laden — gleiche Belegung:
        # Low-Hälfte bei cycle == T_RCD (falls geschrieben), sonst die High-
        # Hälfte; getrieben während der Schreibbefehle, sonst hochohmig.
        ("        dq_oen   <= 1'b1;     // tri-state DQ during init\n", "", "dq_oen aus INIT"),
        ("            dq_out   <= din_buf[15:0];\n            dq_oen   <= 1'b0;\n", "", "dq_out/oen Low-Hälfte"),
        ("            dq_out   <= din_buf[31:16];\n            dq_oen   <= 1'b0;\n", "", "dq_out/oen High-Hälfte"),
        ("            dq_oen <= 1'b1;\n", "", "dq_oen Ende Schreiben"),
        ("        dq_oen     <= 1'b1;\n", "", "dq_oen Reset"),
        ("        rst_done <= 1'b0;\n    end\nend\n\nendmodule",
         "        rst_done <= 1'b0;\n    end\nend\n\n"
         "// Retro25: Datenausgang ohne Clock-Enable (I/O-Register, siehe make_pro.py)\n"
         "always @(posedge clk) begin\n"
         "    dq_out <= (state == WRITE && cycle == T_RCD && wr_halfs[0]) ? din_buf[15:0] : din_buf[31:16];\n"
         "    dq_oen <= !(resetn && state == WRITE &&\n"
         "                (cycle == T_RCD || (cycle == (T_RCD+1) && wr_halfs == 2'b11)));\n"
         "end\n\nendmodule",
         "neuer Block für dq_out/dq_oen"),
        # Z7 (upstream #125): Port 0 (CPU) hatte feste Vorfahrt vor Port 1
        # (DMA). Pollt das BIOS beim Diskettenschreiben, belegt die CPU den
        # Speicher fast durchgehend; die DMA bekam kaum Bytes für den FDC
        # (am Board ~150 B/250 ms) -> BIOS-Zeitüberschreitung, DOS hängt.
        # Wie im PC (HOLD/HLDA) bekommt die DMA Vorrang; sie stellt höchstens
        # eine Anfrage gleichzeitig und kann die CPU nicht aushungern.
        ("    req_id  = valid0 ? 2'd0 :\n              valid1 ? 2'd1 : 2'd2;\n",
         "    req_id  = valid1 ? 2'd1 :     // Retro25: DMA vor CPU (Z7)\n"
         "              valid0 ? 2'd0 : 2'd2;\n",
         "DMA-Vorfahrt"),
    ],
    "z486_mister.sv": [
        # Z7: x87 wie upstream an (ENABLE_X87 = 1, ~5k ALMs); bis Z6 war er aus
        # Neuere MiSTer-sys (unser sys/vendor) verbinden die LFB-Eingänge
        # immer (emu_ports.vh); z486 listet seine Ports noch selbst
        ("\toutput        HDMI_BOB_DEINT,\n",
         "\toutput        HDMI_BOB_DEINT,\n\n"
         "\t// Retro25: wie sys/emu_ports.vh (sys_top verbindet sie immer)\n"
         "\tinput   [5:0] LFB_FMT,\n\tinput  [31:0] LFB_BASE,\n\tinput  [11:0] LFB_WIDTH,\n"
         "\tinput  [11:0] LFB_HEIGHT,\n\tinput  [13:0] LFB_STRIDE,\n",
         "LFB-Ports"),
        # Zusätzlicher hochohmiger Treiber auf dem Gamma-Bus (hps_io <->
        # gamma_corr): Quartus Pro löst die internen Tri-States damit falsch
        # auf (13034/13028, gamma_bus[21] abgetrennt) -> Bild schwarz. Der
        # C64 hat die Zeile nicht.
        ("assign gamma_bus = 'z;\n", "// Retro25: assign gamma_bus = 'z; entfernt (Tri-State-Auflösung, Bild schwarz)\n",
         "gamma_bus ohne Z-Treiber"),
        # Agilex-IOPLL ip/pll_z486 (85 MHz, 85 MHz/90°); "pll" heißt schon das
        # PLL-Modul des HPS-Systems
        ("pll pll\n", "pll_z486 pll\n", "eigene IOPLL"),
        # SDRAM_CLK über das DDIO-Register im I/O-Block wie C64/MemTest:
        # 90° statt upstream 180° (1,8-V-SDRAM, Phasenfenster in cores/sdram486test)
        ("assign SDRAM_CLK     = clk_sdram;",
         "sdram_clk_ddio sdramclk_ddr(.ck(clk_sdram), .din(2'b10), .pad_out(SDRAM_CLK));   // Retro25",
         "SDRAM_CLK über DDIO"),
    ],
    "src/soc/sound/sound.v": [
        # Falle implizite Netze (16788): sbp_stereo_ff_rst wird in Zeile 146
        # benutzt, aber erst später mit "wire x = …" deklariert -> Quartus Pro
        # verwirft die Zuweisung
        ("\nsound_dsp sound_dsp_inst\n",
         "\nwire        sbp_stereo_ff_rst;   // Retro25: vor der ersten Verwendung\n"
         "sound_dsp sound_dsp_inst\n", "Deklaration nach vorn"),
        ("wire sbp_stereo_ff_rst = ", "assign sbp_stereo_ff_rst = ", "Zuweisung statt Deklaration"),
    ],
    # Falle 16754: reg mit Startwert in einem always-Block wird in Quartus Pro
    # jeden Takt zurückgesetzt -> Startwert auf Modulebene
    "src/soc/hps_ext.v": [
        ("reg        dout_en = 0;\n",
         "reg        dout_en = 0;\nreg        cdda_sel = 0;   // Retro25: aus dem always-Block (16754)\n",
         "cdda_sel auf Modulebene"),
        ("    reg        cdda_sel = 0;\n", "", "alte Deklaration raus"),
    ],
    "src/soc/cdda.v": [
        ("always @(posedge CLK) begin\n\treg old_clk;",
         "reg old_wr = 0, rd_req = 0;   // Retro25: aus dem always-Block (16754)\n"
         "always @(posedge CLK) begin\n\treg old_clk;", "old_wr/rd_req auf Modulebene"),
        ("\treg old_wr = 0, rd_req = 0;\n", "", "alte Deklaration raus"),
    ],
    "src/soc/sound/saa1099.sv": [
        # Ports ohne Netztyp ("input clk_sys") unter `default_nettype none ->
        # 17440; ohne Rücksetzen auf wire wirkte es zudem (MFCU) auf die
        # folgenden Dateien (joystick.v).
        ("`default_nettype none\r\n", "", "default_nettype none ohne Netztypen und ohne Rücksetzen"),
    ],
    # Z7 gemeinsamer Ordner (Main x86_share.cpp, DOS-Treiber MISTERFS.EXE des
    # ao486): Der Treiber legt Anfragen in einen 8-KB-Briefkasten bei CE000,
    # Main liest ihn im DDR bei 0x300CE000. Beim ao486 liegt der ganze PC-
    # Speicher im DDR; beim z486 im SDRAM -> CE000-CFFFF wie der lineare
    # Framebuffer als Geräteseite (ungecacht, direkt) ins DDR umleiten.
    "src/z486/z486_pkg.sv": [
        ("    is_device_page = (pfn[19:5] == 15'h5) || (pfn[19:10] == 10'h03E);\n",
         "    is_device_page = (pfn[19:5] == 15'h5) || (pfn[19:10] == 10'h03E) ||\n"
         "                     (pfn[19:1] == 19'h00067);   // Retro25: Briefkasten CE000-CFFFF\n",
         "Briefkasten als Geräteseite"),
    ],
    "src/z486/l1_cache.sv": [
        # Gleiche Ausnahme wie is_device_page an den beiden ausgeschriebenen Stellen
        ("                          (vipt_resolve_phys_addr[31:22] != 10'h03E) &&\n",
         "                          (vipt_resolve_phys_addr[31:22] != 10'h03E) &&\n"
         "                          (vipt_resolve_phys_addr[31:13] != 19'h00067) &&   // Retro25: Briefkasten\n",
         "kein Treffer im Briefkasten"),
        ("                           (vipt_resolve_phys_addr[31:17] != 15'h5) &&\n"
         "                           !(|vipt_hit_vec)",
         "                           (vipt_resolve_phys_addr[31:17] != 15'h5) &&\n"
         "                           (vipt_resolve_phys_addr[31:13] != 19'h00067) &&   // Retro25: Briefkasten\n"
         "                           !(|vipt_hit_vec)",
         "keine Zeilenfüllung im Briefkasten"),
    ],
    "src/memory/main_memory.sv": [
        ("logic [2:0] state;\nlocalparam IDLE = 0;\nlocalparam VGA_READ = 1;\nlocalparam VGA_WRITE = 2;\n"
         "localparam FB_WRITE = 3;\nlocalparam FB_READ  = 4;   // issue DDR3 read\n"
         "localparam FB_READ_WAIT = 5;   // await read data\nlocalparam UNMAPPED_READ = 6;\n\n",
         "", "alte Deklaration state"),
        ("reg   [1:0] vga_mask;\nreg   [1:0] vga_cmp;\n", "", "alte Deklaration vga_mask/cmp"),
        ("// = 0xA0000-0xBFFFF (VGA: exact region depends on VGA_MODE)\n"
         "wire vga_rgn = (cpu_addr[31:17] == 'h5) && ((cpu_addr[16:15] & vga_mask) == vga_cmp);\n",
         "", "alte Deklaration vga_rgn"),
        ("wire lfb_rgn = (cpu_addr[31:22] == 10'h03E);\n",
         "wire lfb_rgn = (cpu_addr[31:22] == 10'h03E);\n"
         "// Retro25: Briefkasten des gemeinsamen Ordners, 0xCE000-0xCFFFF -> DDR\n"
         "// 0x300CE000 (wie ao486; Main x86_share.cpp). Liegt im RAM-Bereich, darf\n"
         "// also nicht ins SDRAM gehen.\n"
         "wire share_rgn = (cpu_addr[31:13] == 19'h00067);\n\n"
         "// Retro25: vor der ersten Verwendung deklariert (Quartus 16749, Questa vlog-2730)\n"
         "logic [2:0] state;\n"
         "localparam IDLE = 0;\nlocalparam VGA_READ = 1;\nlocalparam VGA_WRITE = 2;\n"
         "localparam FB_WRITE = 3;\nlocalparam FB_READ  = 4;   // issue DDR3 read\n"
         "localparam FB_READ_WAIT = 5;   // await read data\nlocalparam UNMAPPED_READ = 6;\n"
         "reg   [1:0] vga_mask;\nreg   [1:0] vga_cmp;\n"
         "// = 0xA0000-0xBFFFF (VGA: exact region depends on VGA_MODE)\n"
         "wire vga_rgn = (cpu_addr[31:17] == 'h5) && ((cpu_addr[16:15] & vga_mask) == vga_cmp);\n",
         "share_rgn, Deklarationen nach vorn"),
        ("assign mem_valid      = cpu_valid && !vga_rgn && !vga_busy && ram_address_in_range(cpu_addr, ram_size);\n",
         "assign mem_valid      = cpu_valid && !vga_rgn && !share_rgn && !vga_busy && ram_address_in_range(cpu_addr, ram_size);\n",
         "Briefkasten nicht ins SDRAM"),
        ("                end else if (cpu_valid && (vga_rgn || lfb_rgn) && !cpu_write &&\n",
         "                end else if (cpu_valid && (vga_rgn || lfb_rgn || share_rgn) && !cpu_write &&\n",
         "Befehls-Zeilenfüllung im Briefkasten wie LFB"),
        ("                end else if (cpu_valid && lfb_rgn) begin\n",
         "                end else if (cpu_valid && (lfb_rgn || share_rgn)) begin\n",
         "Briefkasten über den LFB-Weg"),
        ("                    fb_ddram_addr <= (32'h3F80_0000 | {10'b0, cpu_addr[21:0]}) >> 3;\n",
         "                    fb_ddram_addr <= (share_rgn ? (32'h300C_E000 | {19'b0, cpu_addr[12:0]})\n"
         "                                                : (32'h3F80_0000 | {10'b0, cpu_addr[21:0]})) >> 3;\n",
         "DDR-Adresse des Briefkastens"),
        # Z7 Lesepuffer: Jeder Lesezugriff auf den Framebuffer ist ein
        # einzelner Weg ins DDR (am Board ~42 Takte); Windows 95 mit 256 Farben
        # liest ständig byteweise und wurde zäh. Das zuletzt gelesene 64-bit-
        # Wort bleibt im Puffer; Lesen im selben Wort kommt nach 2 Takten.
        # Schreibt die CPU hinein, werden die Bytes nachgeführt — nur sie
        # schreibt den Framebuffer (der Scaler liest nur). Nicht für den
        # Briefkasten: dort schreibt Main von außen.
        ("localparam UNMAPPED_READ = 6;\n",
         "localparam UNMAPPED_READ = 6;\n"
         "localparam FB_READ_CHK = 7;   // Retro25: Treffer im Lesepuffer?\n"
         "// Retro25: Lesepuffer für den Framebuffer (ein 64-bit-Wort, siehe make_pro.py)\n"
         "reg         rb_valid;\n"
         "reg  [28:0] rb_addr;\n"
         "reg  [63:0] rb_data;\n"
         "reg         rb_hit_r;       // FB_READ_WAIT bedient aus dem Puffer\n"
         "reg         fb_cacheable;   // laufendes Lesen darf den Puffer benutzen\n"
         "wire [63:0] rd64 = rb_hit_r ? rb_data : fb_ddram_dout;\n",
         "Lesepuffer: Deklarationen"),
        ("        fb_linear <= 0;\n    end else begin\n",
         "        fb_linear <= 0;\n"
         "        rb_valid <= 0;\n        rb_hit_r <= 0;\n        fb_cacheable <= 0;\n"
         "    end else begin\n",
         "Lesepuffer: Reset"),
        ("                        state <= FB_READ;\n                        fb_read_high_dword <= cpu_addr[2];\n",
         "                        state <= FB_READ_CHK;\n                        fb_cacheable <= !share_rgn;\n"
         "                        fb_read_high_dword <= cpu_addr[2];\n",
         "Lesepuffer: LFB/Briefkasten"),
        ("                            state <= FB_READ;\n                            if (vga_chain4) begin\n",
         "                            state <= FB_READ_CHK;\n                            fb_cacheable <= 1;\n"
         "                            if (vga_chain4) begin\n",
         "Lesepuffer: banked Fenster"),
        ("                if (!fb_ddram_busy) begin   // DDR3 accepted the write\n                    vga_wr_done <= 1;\n",
         "                if (!fb_ddram_busy) begin   // DDR3 accepted the write\n"
         "                    // Retro25: Lesepuffer nachführen\n"
         "                    if (rb_valid && rb_addr == fb_ddram_addr)\n"
         "                        for (int i = 0; i < 8; i++)\n"
         "                            if (fb_ddram_be[i]) rb_data[i*8 +: 8] <= fb_ddram_din[i*8 +: 8];\n"
         "                    vga_wr_done <= 1;\n",
         "Lesepuffer: Schreiben nachführen"),
        ("            FB_READ:\n",
         "            FB_READ_CHK:\n"
         "                if (fb_cacheable && rb_valid && rb_addr == fb_ddram_addr) begin\n"
         "                    rb_hit_r <= 1;\n"
         "                    state <= FB_READ_WAIT;\n"
         "                end else begin\n"
         "                    rb_hit_r <= 0;\n"
         "                    state <= FB_READ;\n"
         "                end\n"
         "            FB_READ:\n",
         "Lesepuffer: Prüfzustand"),
        (FB_READ_WAIT_OLD, FB_READ_WAIT_NEW, "Lesepuffer: Daten aus Puffer oder DDR"),
    ],
}


def include_copies() -> list:
    """Dateien, die z486_platform.svh einbinden: unverändert nach pro/ kopieren.

    `include sucht zuerst im Ordner der einbindenden Datei — nur so greift die
    angepasste pro/src/z486/z486_platform.svh, ohne VERILOG_CU_MODE MFCU (das
    im Core-Projekt auch auf alle sys-Dateien wirken würde).
    """
    done = []
    for f in sorted((VENDOR / "src" / "z486").rglob("*.sv")):
        rel = f.relative_to(VENDOR).as_posix()
        if rel in PATCHES or '`include "z486_platform.svh"' not in f.read_text(encoding="utf-8"):
            continue
        dst = PRO / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(f.read_bytes())
        done.append(rel)
    return done


def make_pro() -> list:
    done = []
    for rel, subs in PATCHES.items():
        src = (VENDOR / rel).read_bytes().decode("utf-8")
        out = src
        crlf = "\r\n" in src
        for old, new, why, *opt in subs:
            if crlf:                             # Patches mit \n schreiben, hier anpassen
                old = old.replace("\r\n", "\n").replace("\n", "\r\n")
                new = new.replace("\r\n", "\n").replace("\n", "\r\n")
            n = out.count(old)
            first = opt == ["erstes"]
            if n != 1 and not (first and n > 1):
                raise SystemExit(f"{rel}: '{old.strip()}' kommt {n}-mal vor ({why})")
            out = out.replace(old, new, 1)
        dst = PRO / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(out.encode("utf-8"))
        diff = difflib.unified_diff(src.splitlines(keepends=True), out.splitlines(keepends=True),
                                    f"vendor/{rel}", f"pro/{rel}")
        dst.with_name(dst.name + ".patch").write_bytes("".join(diff).encode("utf-8"))
        done.append(rel)
    return done


def cpu_files() -> list:
    """Alle Quellen der CPU (relativ zu src/z486), Pakete zuerst."""
    v = VENDOR / "src" / "z486"
    first = ["z486_pkg.sv", "x87/x87_pkg.sv", "x87/x87_ucode_pkg.sv"]
    rest = sorted(p.relative_to(v).as_posix() for p in list(v.glob("*.sv")) + list(v.glob("x87/*.sv")))
    return first + [f for f in rest if f not in first]


def qip_files(qip: Path) -> list:
    """Quelldateien einer upstream-.qip (rekursiv), relativ zu vendor/."""
    import re
    out = []
    for line in qip.read_text(encoding="utf-8").splitlines():
        m = re.match(r"set_global_assignment -name (\w+)_FILE (?:\[file join \$::quartus\(qip_path\) )?(\S+)", line)
        if not m:
            continue
        kind, path = m.group(1), m.group(2)
        base = qip.parent if "qip_path" in line else VENDOR
        f = (base / path).resolve()
        if kind == "QIP":
            out += qip_files(f)
        elif kind in ("VERILOG", "SYSTEMVERILOG"):
            out.append(f.relative_to(VENDOR.resolve()).as_posix())
    return out


def file_line(rel: str) -> str:
    """qsf-Zeile für eine Datei unter vendor/ (pro/-Kopie, wo vorhanden)."""
    path = ("../pro/" if (PRO / rel).exists() else "../vendor/") + rel
    kind = "VERILOG_FILE" if rel.endswith(".v") else "SYSTEMVERILOG_FILE"
    return f"set_global_assignment -name {kind} {path}"


PROBE_QSF = """# {title} für den A5EB013 (P5/Z2, Synthese-Probelauf) — erzeugt von
# cores/z486/make_pro.py, nicht von Hand ändern.
# Ohne x87 (ENABLE_X87 = 0); alle Ports außer dem Takt als virtuelle Pins:
# der Entwurf wird vollständig platziert und geroutet und liefert echte
# ALM-/M20K-Zahlen und fmax.
set_global_assignment -name FAMILY "Agilex 5"
set_global_assignment -name DEVICE A5EB013BB23BE4SCS
set_global_assignment -name TOP_LEVEL_ENTITY {top}
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name NUM_PARALLEL_PROCESSORS ALL
set_global_assignment -name SEARCH_PATH ../pro/src/z486
set_global_assignment -name SEARCH_PATH ../vendor/src/z486
set_global_assignment -name SEARCH_PATH ../vendor/src/z486/x87
set_global_assignment -name SEARCH_PATH ../vendor/src
set_global_assignment -name SDC_FILE {name}.sdc
set_global_assignment -name OPTIMIZATION_MODE "HIGH PERFORMANCE EFFORT"
# .v-Dateien mit SystemVerilog-Syntax, wie in sys_de25.tcl (MiSTer sys.tcl)
set_global_assignment -name VERILOG_INPUT_VERSION SYSTEMVERILOG_2005
# Eine Übersetzungseinheit für alle Dateien: Makros (Include-Guard der
# angepassten z486_platform.svh) gelten dateiübergreifend
set_global_assignment -name VERILOG_CU_MODE MFCU
set_instance_assignment -name VIRTUAL_PIN ON -to *
set_instance_assignment -name VIRTUAL_PIN OFF -to {clk}
{extra}{files}
"""

PROBE_SDC = """# Ziel wie upstream (Profil production): 85 MHz
create_clock -name clk -period 11.765 [get_ports {clk}]
derive_clock_uncertainty
"""

# Parameter wie in z486_mister.sv (DE10-Nano-Build), aber ohne x87
SYS_PARAMS = {"SYS_FREQ": "85000000", "DCACHE_SET_BITS": "7", "ICACHE_SET_BITS": "7",
              "DCACHE_LINE_WRAP": "1", "ENABLE_X87": "0", "ENABLE_CMS": "0", "ENABLE_VOODOO": "0"}

PROBES = {
    # Name: (Titel, Top-Modul, Taktport, zusätzliche .qip, Parameter)
    "z486_cpu": ("z486-CPU allein", "z486", "clk", None, {}),
    "z486_sys": ("z486-PC ohne MiSTer-Rahmen (Modul system: CPU, VGA, Sound, IDE …)", "system",
                 "clk_sys", "backend.qip", SYS_PARAMS),
}


CORE_TCL = """# core.tcl — z486 im Retro25-Rahmen (P5/Z4; für tools/make_core_qsf.py)
# ERZEUGT von cores/z486/make_pro.py, nicht von Hand ändern.
# {{CORE}} = cores/z486, {{SYS}} = sys, relativ zum Quartus-Projektordner.
# Fremdcode in vendor/; Anpassungen für Quartus Pro/Agilex 5 in pro/ (.patch).
# Mit x87 (Z7). SVGA-Modi ab 256 Farben über den Framebuffer im DDR (MISTER_FB,
# Palette über MISTER_FB_PALETTE; der Scaler liest ab 0x3F800000, wie upstream).
# Takt: ip/pll_z486 (50 -> 85 MHz, zweiter Ausgang 85 MHz/90° für SDRAM_CLK
# über sys/de25/ip/sdram_clk_ddio). Boot-ROMs lädt Main zur Laufzeit
# (games/Z486/boot0.rom, boot1.rom; tools/fetch_z486.py --roms).
set_global_assignment -name SYSTEMVERILOG_FILE {{CORE}}/pro/src/z486/z486_platform.svh
{files}
# MT32-pi-Anbindung (USER_IO) aus MiSTers sys; nur der z486 braucht sie
set_global_assignment -name SYSTEMVERILOG_FILE {{SYS}}/vendor/mister/mt32pi.sv
set_global_assignment -name IP_FILE {{CORE}}/ip/pll_z486.ip
set_global_assignment -name IP_FILE {{SYS}}/de25/ip/sdram_clk_ddio.ip
set_global_assignment -name SDC_FILE {{CORE}}/z486_de25.sdc
set_global_assignment -name SEARCH_PATH {{CORE}}
set_global_assignment -name SEARCH_PATH {{CORE}}/pro/src/z486
set_global_assignment -name SEARCH_PATH {{CORE}}/vendor/src/z486
set_global_assignment -name SEARCH_PATH {{CORE}}/vendor/src/z486/x87
set_global_assignment -name SEARCH_PATH {{CORE}}/vendor/src
set_global_assignment -name VERILOG_MACRO "MISTER_FB=1"
set_global_assignment -name VERILOG_MACRO "MISTER_FB_PALETTE=1"
"""


def make_core() -> None:
    """core.tcl: CPU + backend.qip + z486_mister.sv (Reihenfolge wie files.qip)."""
    rels = [f"src/z486/{f}" for f in cpu_files()] + qip_files(VENDOR / "backend.qip") + ["z486_mister.sv"]
    files = "\n".join(file_line(r).replace("../", "{CORE}/", 1) for r in rels)
    (HERE / "core.tcl").write_text(CORE_TCL.format(files=files), encoding="utf-8", newline="\n")


def make_probe() -> None:
    probe = HERE / "probe"
    probe.mkdir(exist_ok=True)
    cpu = [f"src/z486/{f}" for f in cpu_files()]
    for name, (title, top, clk, qip, params) in PROBES.items():
        rels = cpu + (qip_files(VENDOR / qip) if qip else [])
        # angepasste z486_platform.svh zuerst: ihr Guard gilt für alle Includes
        files = "\n".join(["set_global_assignment -name SYSTEMVERILOG_FILE ../pro/src/z486/z486_platform.svh"]
                          + [file_line(r) for r in rels])
        extra = "".join(f"set_parameter -name {k} {v}\n" for k, v in params.items())
        (probe / f"{name}.qsf").write_text(PROBE_QSF.format(title=title, top=top, name=name, clk=clk,
                                                            extra=extra, files=files),
                                           encoding="utf-8", newline="\n")
        (probe / f"{name}.sdc").write_text(PROBE_SDC.format(clk=clk), encoding="utf-8", newline="\n")
    (probe / "z486.qpf").write_text("".join(f'PROJECT_REVISION = "{n}"\n' for n in PROBES),
                                    encoding="utf-8", newline="\n")
    old = probe / "z486_cpu.qpf"
    if old.exists():
        old.unlink()


def main() -> int:
    for rel in make_pro():
        print(f"pro/{rel}")
    print(f"{len(include_copies())} Dateien mit z486_platform.svh nach pro/ kopiert")
    make_core()
    print("core.tcl")
    make_probe()
    print("probe/z486.qpf mit " + ", ".join(PROBES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
