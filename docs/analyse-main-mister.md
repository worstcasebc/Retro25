# Analyse: Main_MiSTer → aarch64 (DE25-Nano)

Quelle: Main_MiSTer, Commit 00bdff0d (~99 000 Zeilen). Stand 2026-10-14.
Nichts davon gebaut oder ausgeführt — reine Code-Durchsicht.

## Plattformabhängigkeiten

**FPGA-Zugriff (`fpga_io.cpp`)** — gut gebündelt:
- `fpga_io_init()` mappt 0xFF000000 (16 MB) über `/dev/mem`;
  `fpga_gpo_write`/`fpga_gpi_read` greifen auf 0xFF706010/0xFF706014 zu
  (Schattenkopie `gpo_copy`). → auf die LW-Bridge (0x2000_0000) umbiegen.
- `fpga_load_rbf()`: entfernt optionalen 16-Byte-Header „MiSTer“, programmiert
  den FPGA-Manager direkt (ARMv7-Inline-Assembler in `fpgamgr_program_write`),
  `do_bridge()` schaltet Bridges über Reset-Manager/NIC-301.
  → ersetzen durch: rbf nach `/lib/firmware`, configfs-Overlay neu anlegen,
  `status`/`/sys/class/fpga_manager/fpga0/state` prüfen.
- Core-Wechsel: `app_restart()` startet Main per fork+exec mit dem Core-Pfad
  als `argv[1]` neu — passt so.
- `reboot()` (Flag 0xBEEFB001 @0x1FFFFF08), `make_env` (U-Boot-Env @0x1FFFF000),
  `sdram_sz()`/`altcfg()` (Parameterblock @0x1FFFF000) → Linux-Reboot bzw. kleine Datei.
- Darüber (`spi.cpp`, 77 `UIO_*`-Kommandos, OSD) bleibt unverändert.
  Die schnellen Blockfunktionen warten nicht auf ACK → das FPGA-Register muss
  jeden Schreibzugriff in Reihenfolge übernehmen (siehe `hps_gp_bridge`).

**Gemeinsamer DDR (`shmem.cpp`)** — alles über `shmem_map()` mit
`fpga_mem(x) = 0x20000000 | (x & 0x1FFFFFFF)` → Übersetzung an einer Stelle.
Ausnahme: `UIO_SET_FBUF` (video.cpp) schickt eine physische Adresse ans FPGA.

| Adresse | Nutzer | Zweck |
|---|---|---|
| 0x20000000 | scaler.cpp | Screenshots |
| 0x22000000 | video.cpp | Menü-/Linux-Framebuffer |
| 0x30000000 | support/x86 | x86: RAM/BIOS-Fenster |
| 0x300C0000 / 0x300F0000 | support/x86 | boot1.rom / boot0.rom |
| 0x300CE000 | x86_share.cpp | Shared-Folder-Mailbox |

**Video:** `setPLL()`/`findPLLpar()` rechnen Cyclone-V-PLL-Werte (50 MHz
Referenz, M/C/K fraktional) → neu für Agilex-IOPLL. ADV7513 per I2C
(`smbus.cpp` sucht `/dev/i2c-0..2`). Der MiSTer-Framebuffer-Treiber
(`MiSTer_fb`) fehlt in Ubuntu → ersetzen oder stubben.

**Eingabe:** Standard (evdev, uinput, inotify), läuft als root.

**ARMv7/32-bit:** Inline-asm (fpga_io.cpp), `lib/libco/arm.c` → generische
Variante; NEON in scaler.cpp läuft auf aarch64. **Bug:** `unsigned long` in
`RigidDiskBlock`/`PartitionBlock` (`support/minimig/minimig_hdd.h`) wird
8 Byte groß — `ide.cpp` nutzt das bei jedem IDE-Mount, auch für x86 → auf
`uint32_t` ändern. Pointer→`uint32_t`-Casts. CPU-Pinning auf cpu1 → auf dem
Agilex 5 sind cpu2–3 die schnellen A76.

**Build:** Makefile für `arm-none-linux-gnueabihf`; vorgebaute 32-bit-Libs
(imlib2, freetype, png, bz2, z, bluetooth) → durch Ubuntu-arm64-Pakete
ersetzen. Am einfachsten **nativ auf dem Board bauen**.

**Layout:** `/media/fat` als Wurzel, `MiSTer.ini`, Statusdateien in `/tmp`.
Optionale Helfer (uartmode, btpair …) dürfen fehlen.

**Menü-Core:** `menu.rbf` ist ein echter FPGA-Core; das OSD zeichnet das FPGA.

## x86 (z486)

- Bereits unterstützt: `is_x86()` kennt AO486, PC110, Z486, Z386.
- Festplatte/CD über den gp-Bus (`ide_check` → `ide_io`, bis 32 Sektoren je
  Burst), Diskette 0xF200, CMOS 0xF400 — nicht über DDR.
- DDR trotzdem nötig: Boot-ROMs, UMA-Füllung, Mailbox.
- `ide.cpp` ruft `a2065_poll()` → minimig-Teil mitbauen oder stubben.
- Minimum zum Booten: gp-Nachbildung, `user_io_init`, `x86_init/x86_poll`,
  Tastatur/Maus, OSD (oder vorbelegte `z486sys.cfg`), DDR-Fenster; Video zuerst fest.

## Aufwand (Schätzung des Analyse-Agenten)

| Teil | Personentage |
|---|---|
| aarch64-Build | 2–4 |
| fpga_io (gp-Register + Overlay-Laden) | 4–7 (+3–6 FPGA) |
| DDR-Speicherkarte | 3–5 |
| Rest (IOPLL-Mathematik, HDMI-I2C, FB-Ersatz, Dienste, Tests) | 8–20 |
| **Bring-up mit Platzhaltern** | **~2–3 Wochen** |
| **Voller Port** | **~5–8 Wochen** (FPGA-Seite dominiert) |

## Risiken

1. **Lesezugriff auf die LW-Bridge während des Neuladens → SError, Kernel-Absturz.**
   Alle Bridge-Zugriffe beim Core-Wechsel sperren.
2. Video-PLL-Mathematik für IOPLL.
3. `/dev/mem`-Politik des Terasic-Kernels (`CONFIG_IO_STRICT_DEVMEM`) prüfen.
4. Plattendurchsatz über den gp-Bus.
5. 64-bit-Struct-Bug (s. o.).

Für den Bring-up stubbar: `make_env`, Parameterseite, `do_bridge`, `setPLL`,
HDMI-I2C/CEC, `MiSTer_fb`, `vs_wait`, Screenshots, Bluetooth, uartmode,
x86_share, Menü-Core (Main direkt mit dem Core als `argv[1]` starten).
