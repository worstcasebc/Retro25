# Roadmap: z486 (486-PC-Core) auf dem DE25-Nano

Stand: 2026-10-14 (überarbeitet nach der Entscheidung für den vollen
MiSTer-Port). Gesamtplan: [roadmap.md](roadmap.md), Fakten zum Core:
[analyse-z486.md](analyse-z486.md).

## Ausgangslage

- **Quelle:** [z486](https://github.com/nand2mario/z486) (CPU) +
  [z486_MiSTer](https://github.com/nand2mario/z486_MiSTer) (kompletter PC als
  MiSTer-Core). Leistung etwa 486DX2-66, experimentelle x87-FPU.
- **Voraussetzung:** Phasen P0–P3 der Gesamt-Roadmap. Der z486 braucht das
  portierte `sys/` samt F2SDRAM und ascal (Boot-ROMs und SVGA-Framebuffer
  liegen im DDR) sowie Main_MiSTer (Platten, Diskette, CMOS laufen über
  `hps_ext` und den x86-Teil von Main).
- Damit entfällt die frühere Idee, `hps_io` durch eigene Register zu
  ersetzen: Wir bauen MiSTers Kupplung selbst nach, statt den Anhänger
  umzubauen.

## Phasen

**Z1 — Simulation (parallel zu P0–P3 möglich):** Verilator-Umgebung des
Repos unter WSL2 zum Laufen bringen, FreeDOS-Image (`verilator/freedos.zip`)
booten, optional 86Box-Co-Simulation. Lernziel: CPU-Bus, Speicherkarte,
Boot-Ablauf verstehen; Referenz für spätere Tests.

**Z2 — Synthese-Probelauf:** z486-Core (ohne x87, dann mit) in einem
Quartus-Pro-Projekt für den A5EB013 übersetzen. RAM-Abbildung über
`z486_platform.svh` auf M20K/MLAB, `altsyncram`/`altera_pll` ersetzen.
Ergebnis: echte ALM-/M20K-Zahlen und fmax statt Schätzung; Entscheidung
x87 ja/nein und Ziel-Takt (50/65/85 MHz).

  **Erledigt 2026-10-18** (ohne x87, `cores/z486/probe`, erzeugt von
  `cores/z486/make_pro.py`; alle Ports als virtuelle Pins, voll geroutet):

  | Probe | ALMs | M20K | DSP | fmax (Ziel 85 MHz) |
  |---|---|---|---|---|
  | CPU (`z486`) | 17 647 | 49 | 4 | 105,9 MHz |
  | PC ohne MiSTer-Rahmen (`system`) | 25 689 | 209 | 5 | 104,6 MHz |

  85 MHz ohne Seed-Sweeps mit ~20 MHz Reserve. Mit dem damaligen sys/
  (Menü-Core 22k ALMs, 190 M20K) hätte es nicht gepasst; das HPS-System
  aus Terasics GHRD wurde deshalb verschlankt (`sys/de25/hps_slim.tcl`:
  Menü-Core jetzt 13,7k ALMs, 59 M20K). Für Quartus Pro/Agilex 5 waren
  8 Anpassungen nötig (je mit Grund in `make_pro.py`): `default_nettype
  none` mit `input logic` (2×), `altsyncram` mit zweitem Takt im
  True-Dual-Port (2×), `ramstyle "M10K"` (Header als erste Datei +
  `VERILOG_CU_MODE MFCU`), `.v` als SystemVerilog, und zwei stille Fallen:
  IDE-Puffer in Logik statt RAM (Lese-/Schreibverhalten → `no_rw_check`,
  sonst 374k ALMs) und VGA-Planes doppelt (Port B synchron lesen). x87
  bleibt für Z7.

**Z3 — SDRAM:** `sdram.v` an den Onboard-Chip anpassen (`HAS_DQM=1`,
Adressaufteilung Einzelchip, CL/Timing, Takt-Phase, Agilex-I/O-Register).
Datenblatt nach `docs/`. Test mit Mustergenerator + Signal Tap.
*Erledigt 2026-10-18:* upstreams `sdram.v` läuft unverändert im Timing
(85 MHz, CL2, `HAS_DQM=1`, 128 MB über beide Chips); nur Quartus-Pro-Anpassungen
in `make_pro.py` (I/O-Register ohne Enable). Testcore `cores/sdram486test`
mit Testbench und Chip-Modell: Phasenfenster `SDRAM_CLK` 0°…135°, gewählt 90°
(wie C64). Signal Tap war nicht nötig.

**Z4 — Integration in sys/:** z486 als Core im portierten Framework, PLL
als IOPLL (unter den Bedingungen aus P0), Boot-ROMs von Main ins DDR.
Ziel: BIOS-POST auf dem Bildschirm.
*Erledigt 2026-10-18:* BIOS-POST am Board (Bochs-BIOS, ET4000 2 MB,
„No bootable device“). Ohne x87 und Framebuffer: 38,1k ALMs (81 %), 268 M20K,
85 MHz. Boot-ROMs lädt Main über den DDR (nicht „von Main ins DDR“ als eigener
Schritt: Main schreibt, der Core kopiert sie beim Reset ins SDRAM). Fallen:
`gamma_bus = 'z` (Bild schwarz), Main-SIGBUS in `x86_init` (Patch 0006).
Details `cores/z486/README.md`.

**Z5 — Platten & Boot:** IDE über `hps_ext` + Main x86-Teil, FreeDOS von
`.vhd`. Der große Meilenstein.
*Erste Stufe erledigt 2026-10-18:* FreeDOS 1.3 (upstream-Testplatte, 32 MB)
bootet von IDE 0-0 bis `C:\>`, Tastatur geht — ohne Änderung an Core oder
Main. OSD bei PC-Cores mit Win + F12; Platte merkt Main erst mit „Save
settings“. Offen: größere/eigene Platten, Diskette, CD-ROM, Schreibtest.

**Z6 — Eingabe & Sound:** PS/2-Tastatur/Maus über Main, SB16/OPL3 über
HDMI-Audio. Ziel: Doom spielbar.
*Erledigt 2026-10-18:* Doom-1.9-Shareware von einer Datenplatte
(`tools/make_dos_disk.py`) läuft flüssig mit Sound-Blaster-Musik und -Effekten
über HDMI, Tastatur über Main; timedemo demo3 = 37,0 fps.
*2026-10-19:* Maus (nach Main-Patch 0007, Kernel ohne mousedev) und
USB-Gamepads am Game-Port (nach „Define joystick buttons“ im z486) gehen,
beide in Doom geprüft.

**Z7 — Kür:** x87 (Quake), Disketten-Images, CD-ROM, SVGA-Modi, Windows 3.1/95.
*2026-10-19:* CD-ROM (ISO an IDE 1-0, FreeDOS UDVD2 + SHSUCDX) und
Diskette lesen gehen. *2026-10-20:* Diskette schreiben geht (upstream #125:
SDRAM-Arbiter gab der CPU Vorfahrt vor der DMA → DMA bekommt Vorrang).
Windows 95 OSR2 installiert und startet (Images vom USB-Stick); Schreiben
auf Images ~8–10× schneller nach Main-Patch 0008 (ohne `O_SYNC`).
*2026-10-22:* Gemeinsamer Ordner (MISTERFS, `games/Z486/shared` als
Netzlaufwerk) geht unter DOS: Briefkasten `CE000` im Core ins DDR geleitet,
Main-Patch 0009; dabei in `sys` gefunden: DDR-Lesen braucht byteenable FF.
SVGA-Framebuffer (`MISTER_FB`) aktiv: 640×480×256 unter DOS (VESA) und
Windows 95 (ET4000-Treiber, bis 1024×768); Lesepuffer im Framebuffer
macht das Lesen 1,6–2,6× schneller.
x87-FPU an (92 % ALMs, 85 MHz): FPUTEST bitgenau, FMUL ~9 Mio/s. Quake 1.06
timedemo demo1 = 8,3 fps.
Details `cores/z486/README.md`.

## Risiken

- **Timing:** Upstream schafft 85 MHz auf Cyclone V nur mit Seed-Sweeps;
  auf Agilex 5 laut Z2 ~105 MHz ohne Optimierung (ohne MiSTer-Rahmen).
- **Platz:** laut Z2 ~39k von 46,8k ALMs (mit schlankem HPS-System);
  x87 (+~5k) wird eng.
- **SDRAM-Bandbreite:** CPU und VGA teilen sich 16 bit; `split_sdram_backend`
  erst verstehen, dann ändern.
- **Main-Version:** z486 braucht Main_MiSTer ≥ 20260823 — beim Port diesen
  Stand oder neuer verwenden.
- **Lizenz:** Microcode (`ucode.hex`) ist von Apache 2.0 ausgenommen →
  Bitstreams nicht weitergeben.
