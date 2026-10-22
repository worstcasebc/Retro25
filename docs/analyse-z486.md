# Analyse: z486_MiSTer → DE25-Nano

Quelle: z486_MiSTer (CPU-Submodul `src/z486` @ 8251185). Upstream baut für
Cyclone V 5CSEBA6 mit Quartus 17.0.2 Lite. Stand 2026-10-14.

## Takte

- `clk_sys` 85 MHz (Profil „production“, 180°); weitere Profile: 50 MHz/225°
  („base“), 65 MHz/180° („debug“). `rtl/pll*` ist gitignored → Profil aus
  `profiles/` kopieren. SDRAM-Takt = zweiter PLL-Ausgang, phasenverschoben.
- `CLK_VIDEO` = `clk_sys` mit fraktionalem `CE_PIXEL`; `CLK_AUDIO` 24,576 MHz.
- CPU-Geschwindigkeit im OSD (Full/56/30/15) ist eine Bremse
  (`cpu_throttle.sv`), keine PLL-Umschaltung.
- 85 MHz schließt Upstream auf Cyclone V nur mit Seed-Sweeps.

## Was der Core von hps_io / Main braucht

- `WIDE=1`, 128-bit-Status, Name `Z486`; Mounts S0–S5 (Diskette A/B, IDE0,
  IDE1 VHD/ISO/CUE/CHD).
- **Platten laufen über EXT_BUS → `hps_ext` (Kommandos 0x61–0x63)** auf einen
  Verwaltungsbus: F0xx IDE0, F1xx IDE1, F2xx Diskette, F3xx CD-Audio,
  F4xx CMOS/RTC. Bedient vom x86-Teil in Main_MiSTer. `sd_*`/`img_*` unbenutzt.
- PS/2-Tastatur und -Maus (`PS2WE=1`), Gameport.
- `sdram_sz` aus hps_io legt die SDRAM-Geometrie fest.
- Braucht Main_MiSTer ≥ 20260823.

## DDR (über F2SDRAM)

- Boot-ROMs: Main legt `boot1.rom` nach 0x300C0000, `boot0.rom` nach
  0x300F0000; der Core kopiert sie bei jedem Reset ins SDRAM.
- SVGA-Framebuffer (~0x3E000000), den der Scaler (ascal) liest
  (`MISTER_FB`, `MISTER_FB_PALETTE`). → ohne F2SDRAM + ascal kein z486.

## SDRAM

- `sdram.v` über `split_sdram_backend`, ein Takt (85 MHz), CL2 bis 100 MHz,
  Burst 1, Auto-Precharge.
- Für MiSTer-Module ohne DQM geschrieben (`HAS_DQM=0`: DQM-Pins als A11/A12,
  Byte-Schreiben als Read-Modify-Write). 128 MB = zwei 64-MB-Chips mit
  Chip-Select über addr[26].
- **Für DE25:** `HAS_DQM=1` (Onboard-Chip hat DQM), Adressaufteilung für den
  Einzelchip anpassen, Takt-Weiterleitung und I/O-Timing für Agilex 5 neu.
  Datenblatt des Onboard-SDRAMs nach `docs/` legen.

## Video und Audio

- VGA aus ao486 mit ET4000-Erweiterung; 4 × 64 KiB Planes on-chip (~2 Mbit).
- Pixeltakt per Akkumulator (25,175/28,322/32,514/35,9 MHz).
- Sound: SB16-DSP, OPL3, PC-Speaker, CD-Audio, MT32-pi (USER-Port, abklemmbar).

## Herstellerspezifisches im Core

- `altsyncram` „Cyclone V“: `ucode_rom.sv` (4K × 40, `ucode.mif`), x87-ROMs,
  `common/dpram.v`; `altdpram`/MLAB in `simple_fifo_mlab.v`; `altera_pll`.
- `z486_platform.svh` bildet `Z486_BLOCK_RAM` → M10K und
  `Z486_DISTRIBUTED_RAM` → MLAB ab — guter Ansatzpunkt für eine
  Agilex-Variante (M20K); `$readmemh`-Fallbacks existieren.
- DSP: 17×17-Multiplizierer, x87 27×26.
- SDC nur false paths; qsf-Makros `Z486_QUARTUS_M10K_UCODE`, `Z486_ALTERA_ALU`,
  `MISTER_FB`, `MISTER_FB_PALETTE`.

## Ressourcen

CPU allein (Cyclone V): **21 906 ALMs mit x87, 16 329 ohne**. Gesamtschätzung
mit sys/ (unbestätigt): 35–40k ALMs bei 46,8k verfügbaren → eng.
Block-RAM früh prüfen (VGA-Planes, Caches, Microcode, ascal).

## Lizenz

- CPU: Apache-2.0 nur für `*.sv`, `*.svh`, `*.py`, `*.md`. **`ucode.hex`
  (rekonstruierter Intel-386-Microcode) und daraus erzeugte Dateien sind
  ausgenommen** → privat bauen in Ordnung, Weitergabe von Bitstreams ungeklärt.
- z486_MiSTer hat keine LICENSE-Datei.
- `boot0.rom` = Bochs-BIOS (LGPL), `boot1.rom` = Tseng-ET4000-BIOS (proprietär).

## Simulation

Verilator 5 + SDL2 + libpng, C++17 → unter **WSL2**. `--cosim` vergleicht
nach jedem Befehl mit dem 86Box-CPU-Kern (Submodul, unter Windows
Pfadlängenproblem → in WSL klonen). `verilator/freedos.zip` enthält ein
32-MiB-FreeDOS-Image; `boot0.rom` (64 KiB) und `boot1.rom` (32 KiB) liegen bei.
