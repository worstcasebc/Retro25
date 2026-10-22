# Roadmap Retro25: MiSTer auf dem DE25-Nano

Stand: 2026-10-14. Grundlage: [analyse-mister-sys.md](analyse-mister-sys.md),
[analyse-main-mister.md](analyse-main-mister.md), [analyse-z486.md](analyse-z486.md).
Details zum z486: [roadmap-z486.md](roadmap-z486.md).

## Zielbild

Wie beim MiSTer: Nach dem Einschalten bootet Linux, Main_MiSTer startet und
lädt den Menü-Core; mit F12 wählt man einen Core (C64, z486 …), Main lädt
dessen `.core.rbf` ins FPGA und bedient ihn (Disks, Tastatur, OSD).

Analogie: `sys/` ist die Konsole mit Netzteil, Bildschirmanschluss und
Steckplatz; jeder Core ist ein Modul, das in diesen Steckplatz passt. Main_MiSTer
ist der Bediener, der Module tauscht und ihnen Disketten reicht.

## Was sich gegenüber dem C64-Projekt ändert

| Thema | C64-DE25 | Retro25 |
|---|---|---|
| Boot | FPGA-first, ganzes Design im QSPI | **HPS-first**: QSPI nur I/O-Ring + Bootloader, Core von SD |
| Linux-Seite | eigener Python-Dienst `c64d.py` | **Main_MiSTer** (C++, portiert) |
| FPGA-Rahmen | eigenes Top-Level | portiertes MiSTer `sys/` (sys_top, hps_io, ascal, OSD) |
| HPS↔FPGA | eigene Register an der LW-Bridge | nachgebildete gp_out/gp_in an der LW-Bridge + F2SDRAM |
| Video | eigener Upscaler, fest 720p50 | ascal-Scaler, Modus per Main/INI |

Übernommen werden Erfahrungen und verifizierte Fakten (Pins, HDMI-Init,
Quartus-Pro-Eigenheiten, GHRD-Handhabung, Board-Setup).

## Phasen (jede endet testbar)

### P0 — Core-Wechsel-Machbarkeit
Ziel: Beweisen, dass Linux das Fabric im Wechsel neu laden kann, bevor Arbeit
in den Port fließt.
- GHRD auf HPS-first umstellen; `.jic` (I/O-Ring + FSBL) ins QSPI, U-Boot
  lädt `core.rbf` von der SD-Karte.
- Zwei Mini-Cores (LED-Lauflicht A/B, gleiche Pins, gleiches HPS-System),
  einer mit abweichender PLL-Einstellung.
- Aus Linux per Overlay im Wechsel laden (≥ 20 Mal); LW-Bridge-Register vor
  und nach dem Laden lesen.
- **Fragen, die P0 beantwortet:**
  1. Stabil bei wiederholtem Laden (bekannte Agilex-5-Fehler in 24.1)?
  2. Ändert eine andere PLL-Einstellung den `IO hash`? Wenn ja: alle PLLs
     nach `sys/` mit festen Frequenzen + Laufzeit-Rekonfiguration.
  3. Bleibt die LW-Bridge nutzbar; braucht es Freeze-Bridge-Knoten im DT?
  4. Erlaubt der Kernel `/dev/mem` auf LW-Bridge und reserviertes DDR?
  5. Wo liegt das DDR physisch, wie adressiert F2SDRAM?
  6. Kann die IOPLL fraktional (für die HDMI-PLL)?

### P1 — sys/-Grundport mit Direktvideo
- `sys_top_de25.v` mit unveränderter `emu`-Instanz, Makros
  `MISTER_DEBUG_NOHDMI`, `MISTER_DISABLE_ALSA`, `MISTER_DISABLE_YC` und neuem
  `MISTER_DE25` (Analogboard, I/O-Board, User-Port, ADC, SD-SPI weg).
- `hps_gp_bridge` (gp_out/gp_in an der LW-Bridge) — eigenes Modul mit Testbench.
- Feste IOPLLs (Core, Audio), HDMI-Takt per GPIO-DDR, HDMI-I2C-Weg klären
  (Option: Altera-I2C-IP im HPS-System → Linux-Treiber `i2c-altera` →
  `/dev/i2c-N`, so wie Main es erwartet).
- Test-Core (Template_MiSTer) zeigt ein Bild über HDMI; ein Python-Skript
  liest über die Bridge die Kennung `0x5CA623`.

### P2 — Main_MiSTer minimal — erledigt (2026-10-15)
- Nativ für aarch64 bauen; libco, Struct-Bug, Casts, Libs.
- `fpga_io`: gp-Zugriff über LW-Bridge, `fpga_load_rbf` über Overlay,
  Bridge-Zugriffe während des Ladens sperren.
- Main startet mit dem Test-Core als `argv[1]`.
- Ziel: F12 öffnet das OSD des Cores, USB-Tastatur geht.

**Ergebnis:** Main_MiSTer (Commit 00bdff0) läuft auf dem Board, Details in
`linux/main/README.md`. Geprüft mit `cores/testpattern`: F12-OSD,
Menüeinträge wirken auf den Core, Core-Neuladen aus dem Menü (SSH über WLAN
übersteht es dank `retro25-switch-hook`), Start mit dem von U-Boot geladenen
Core, Autostart als systemd-Dienst. Unterwegs gelernt:
- libco fällt auf aarch64 auf `sjlj.c` zurück; Ubuntus `_FORTIFY_SOURCE`
  bricht dessen Stackwechsel ab → für `libco.c` abgeschaltet.
- Nach dem Laden durch U-Boot meldet der FPGA-Manager `unknown` statt
  `operating`; Main prüft dann die ID der `hps_gp_bridge` (Lesen bei
  fremdem Kern gefahrlos, ID 0).
- `app_restart` per `execl` statt doppeltem `fork`, damit systemd Main
  nach einem Core-Wechsel nicht verliert.
- **Verschoben nach P3:** ADV7513 über Main. Bis dahin stellt
  `hdmi_config` im FPGA den Sender fest auf 720p60 ein.

### P3 — F2SDRAM, Scaler, Menü-Core → Core-Auswahl per F12 — erledigt (2026-10-16)
- F2SDRAM mit den drei sysmem-Ports (Arbitrierung, Taktübergang,
  Adress-Offset), reserved-memory im Device-Tree.
- **Entschieden (2026-10-15):** drei Avalon-Ports in `qsys_top` exportieren
  (Platform Designer übernimmt Arbiter, Breite, Takt; HPS-IP unverändert);
  DDR-Fenster obere 512 MB `0xA000_0000–0xBFFF_FFFF` (MiSTer-Adresse + Bit 31),
  Reservierung per `fdt` im U-Boot-Skript. Reihenfolge und Stand in
  `p3/README.md`.
- ascal aktiv, HDMI-PLL mit IOPLL-Reconfig und angepasster PLL-Rechnung in Main
  (**erledigt 2026-10-16**, Schritte 3 und 4 in `p3/README.md`).
- ADV7513 über Main: Der Sender hängt an FPGA-Pins, nicht am I2C des HPS.
  Kleiner I2C-Master im FPGA, den Main über die LW-Bridge anspricht (Ersatz
  für `smbus.cpp` in `linux/main/de25/`); löst `hdmi_config` ab. Nötig, sobald
  Main Videomodi wechselt (Infoframes, Audio, Ein/Aus bei Moduswechsel).
  **Erledigt 2026-10-16;** `hdmi_config` bleibt für die Zeit vor Main.
- Menü-Core läuft; Core-Liste, Laden, Rückkehr ins Menü (**erledigt
  2026-10-16**, Schritt 5 in `p3/README.md`; DDR-Sperre vor dem Umladen).
- **Meilenstein: Core-Auswahl über F12 wie beim MiSTer — erreicht.**

### P3a — SD-Karte schützen (entschieden 2026-10-16, erledigt 2026-10-17)
Anlass: Harte Resets während der Core-Wechsel-Fehlersuche haben das
ext4-Root der SD-Karte zerstört (Rettung mit `tools/sd_rescue.py`).
- Root (`mmcblk0p2`, auf 8 GiB verkleinert) schreibgeschützt; Daten auf
  neuer Partition `mmcblk0p3` (ext4, `/media/fat`); Logs, Journal und
  Zustandsdateien im RAM; Main legt den Core unter `/run` ab. Wartung mit
  `retro25-rw`/`retro25-ro`. Details in `linux/system/README.md`.
- Magic SysRq frei: Hänger über die serielle Konsole sauber neu starten
  statt Reset-Knopf. Feste MAC-Adresse, damit die IP gleich bleibt.
- Weiterhin vor jedem Test, der das Board aufhängen kann: `sync`.
- Root auf USB-SSD: geprüft und verworfen.

### P4 — C64
- **Entschieden (2026-10-17): MiSTers C64_MiSTer als Basis** (Fremdcode
  unter `cores/c64/vendor/`, Anpassungen als Kopie + Patch). Grund:
  `C64-DE25` ist im Kern derselbe MiSTer-Code (T65, VIC-II, SID, CIA, 1541)
  mit eigenem Rahmen und weniger Funktionen; MiSTers Core passt direkt an
  `emu`/`hps_io` und bringt CRT, TAP, REU, 8580, NTSC mit. `C64-DE25` dient
  als Vorlage für die Quartus-Pro-Patches.
- Hürden: Der Core braucht **SDRAM** (C64-RAM, REU, Cartridges).
  **Schritt 1 erledigt (2026-10-17):** MiSTers MemTest portiert
  (`cores/memtest`). Das onboard-SDRAM (1,8 V) läuft bei 64 MHz fehlerfrei,
  wenn `SDRAM_CLK` gegenüber dem Core-Takt um 45–135° versetzt ist;
  MiSTers invertierter Takt (180°) fällt durch. Entschieden: Der C64
  bekommt einen PLL-Ausgang clk64 +90° über `sdram_clk_ddio`. Dazu
  I/O-Register für die SDRAM-Pins in `sys_de25.tcl` (wie MiSTer).
- Schritte 2/3 erledigt (2026-10-18): `tools/fetch_c64.py`, ROMs lokal
  (`tools/make_c64_roms.py`), feste PLL nur PAL (entschieden), Quartus-Pro-
  Anpassungen (`cores/c64/README.md`). Schritt 4 Board-Test: BASIC, PRG, SID,
  Tastatur, Diskette lesen und schreiben ok (dafür `sys/de25/avl_burst_4k.v`:
  Bursts über 4-KB-Grenzen vertrug F2SDRAM nicht). **P4 erledigt
  (2026-10-18):** dazu CRT (auch Bankumschaltung), TAP, Joysticks, Ton
  (Testmedien `cores/c64/test/make_test_media.py`). Die **ROMs** liegen bei
  MiSTer als `.mif` im Quellcode → nicht einchecken, lokal aus `roms/`
  erzeugen. Laufwerk und Datasette nutzen DDRAM → Burst-Regel aus P3 prüfen.
- Offen: Lizenz des FPGA64-Codes (VIC-II, Buslogik) ohne Vermerk — vor einer
  Veröffentlichung klären.

### P5 — z486
Siehe [roadmap-z486.md](roadmap-z486.md): Verilator-Simulation (parallel ab
sofort möglich), SDRAM-Anpassung, BIOS-POST, FreeDOS von VHD, Sound, x87.
Z2 (Synthese-Probelauf) erledigt 2026-10-18; dafür das HPS-System
verschlankt (`sys/de25/hps_slim.tcl`, alle Cores neu gebaut).

### P6 — Komfort
Video-Modi/INI, Low-Latency-Modus, ALSA, UART/MIDI, Screenshots,
Shared Folder, weitere MiSTer-Cores.

## Größte Risiken

1. ~~Neuladen des Fabrics auf Agilex 5~~ — **P0 bestanden** (2,1 s je Wechsel,
   30+ Wechsel fehlerfrei, `reboot` geht; nur der USB-WLAN-Stick stolpert).
2. ~~PLLs als Teil des I/O-Rings~~ — **in P0 entschärft:** Eine eigene PLL
   ändert zwar den `IO hash`, der Kern lädt und läuft aber korrekt; bindend ist
   nur der `HPS IO hash`. Jeder MiSTer-Core behält seine `rtl/pll` (als
   Agilex-IOPLL neu erzeugt). Laufzeit-Umstellen nur für die HDMI-PLL.
3. F2SDRAM: ein AXI-Port statt drei Avalon-Ports; ohne ihn kein Menü-Core, kein z486.
4. HDMI-PLL: IOPLL vermutlich nur ganzzahlig → Main-Rechnung und Low-Latency neu.
5. Platz: z486 + sys/ — Z2 gemessen: PC ohne Rahmen 25,7k ALMs/209 M20K,
   sys/ mit schlankem HPS-System ~13k ALMs/~57 M20K → ~39k von 46,8k.
6. Lizenz z486-Microcode: nur privat bauen.
