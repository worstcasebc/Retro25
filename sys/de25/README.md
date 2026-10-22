# sys/de25 — MiSTers Framework auf dem DE25-Nano

MiSTers `sys/` (unverändert in `sys/vendor/mister`, holt `tools/setup.py`) ist für den Cyclone V des
DE10-Nano geschrieben. Hier liegen die Ersatzteile für das Agilex 5 des
DE25-Nano. Ziel: Jeder MiSTer-Core (`module emu`, `sys/emu_ports.vh`,
`hps_io`) läuft unverändert darauf; nur seine PLL wird als Agilex-IOPLL neu
erzeugt.

## Dateien

| Datei | Zweck |
|---|---|
| `sys_top_de25.v` | Top-Level, abgeleitet von `sys_top.v` (Änderungen mit „DE25:“ markiert) |
| `hps_gp_bridge.v` | gp_out/gp_in des Cyclone-V-HPS als Register an der LW-Bridge (`0x2001_0100`) |
| `sysmem_de25.v` | Ersatz für `sysmem_lite`: Takt, Reset, drei DDR-Ports (vbuf/ram1/ram2) an F2SDRAM, Adressen ins Fenster `0xA000_0000` |
| `avl_burst_4k.v` | teilt Avalon-Bursts an 4-KB-Grenzen (AXI-Regel des F2SDRAM), hinter jedem `f2s_halt_de25` |
| `f2s_halt_de25.v` | hält einen DDR-Port vor dem Umladen sauber an (ein Exemplar je Port in `sysmem_de25`); Register `0x2001_7000` für Main (`p3/linux/f2s_halt.py`) |
| `hps_bridges.tcl` | qsys-Skript: Avalon-Brücken `c64_m0` (gp-Register) und `disk_m0` (übrige Register) an der LW-Bridge, wie im C64-Projekt von Hand (wendet `tools/fetch_hps.py` zuerst an) |
| `hps_f2sdram_ports.tcl` | qsys-Skript: drei Avalon-Ports (Clock Crossing Bridges) in `qsys_top` (wendet `tools/fetch_hps.py` an) |
| `hps_slim.tcl` | qsys-Skript: GHRD-Demo- und Debug-Teile raus, FPGA→HPS-Bridge aus (P5, siehe unten; wendet `tools/fetch_hps.py` danach an) |
| `video_debug.v` | Messpunkte der Videokette, Linux liest sie an `0x2001_4000` (`p3/linux/video_debug.py`) |
| `ip/pll_hdmi_de25.ip` | HDMI-PLL (HVIO-IOPLL mit Umkonfigurations-Port), Startwert 148,5 MHz |
| `pll_cfg_de25.v` | Ersatz für `pll_cfg`: nimmt Mains PLL-Register (Cyclone-V-Format) und stellt die IOPLL über `core_avl_*` um; Debug-Register an `0x2001_5000` (`p3/linux/pll_cfg.py`) |
| `i2c_master_de25.v` | byteweiser I2C-Master für den HDMI-Sender, Linux an `0x2001_6000` (Main: `linux/main/de25/smbus.cpp`, Test: `p3/linux/i2c_test.py`) |
| `avl_slow_cdc.v` | trägt einzelne LW-Bridge-Zugriffe von `clk_100` in die Domäne von CLOCK0_50 |
| `pro/*.sv`, `pro/*.v` | für Quartus Pro angepasste Kopien von MiSTer-Dateien (nicht im Repository; `tools/apply_patches.py` erzeugt sie aus `sys/vendor` und den `*.patch`) (siehe unten); seit dem C64 auch die Video-Hilfsmodule, die Cores selbst einbinden (`video_mixer`, `hq2x`, `gamma_corr`, `video_cleaner`, `arcade_video`) |
| `hdmi_config.v`, `i2c_write.v` | HDMI-Sender ADV7513 einstellen (aus C64-DE25), solange Main den Bus nicht übernommen hat (Bild auch ohne Main) |
| `sync_2ff.v` | Synchronizer |
| `ip/sdram_clk_ddio.ip` | DDIO-Ausgaberegister (GPIO-IP) für `SDRAM_CLK`: `din[1]` bei Takt high, `din[0]` bei low — `2'b10` gibt den Takt 1:1 aus (siehe P4 unten) |
| `ip/pll_audio.ip` | 24,576 MHz für den Ton (50 MHz × 29 / 59 = 24,57627 MHz, +11 ppm) |
| `sys_de25.tcl` | gemeinsame Quartus-Einstellungen und Pins aller Cores |
| `sys_top_de25.sdc` | Timing-Vorgaben |

Ein Core-Projekt entsteht mit `python tools/make_core_qsf.py <core>` aus
`sys_de25.tcl` und `cores/<core>/core.tcl`; gebaut wird mit
`Q:\tools\build_core.bat <core>`.

## Was gegenüber dem DE10-Nano anders ist

| Thema | DE10-Nano (Cyclone V) | DE25-Nano |
|---|---|---|
| gp_out/gp_in | Register im HPS | `hps_gp_bridge` an der LW-Bridge, Schreiben mit Handshake |
| DDR-Zugang (ascal, DDRAM, ALSA) | 3 × fpga2sdram | 3 Avalon-Bridges → AXI4-F2SDRAM, Fenster `0xA000_0000–0xBFFF_FFFF` (P3) |
| HDMI-Sender einstellen | Main_MiSTer über HPS-I2C | Main über `i2c_master_de25` (LW-Bridge); vorher `hdmi_config` |
| HDMI-PLL | fraktional, `pll_cfg` + `pll_hdmi_adj` | nur ganzzahlig: Main rechnet N/M/C (Patch `0004`), `pll_cfg_de25` übersetzt; ohne `pll_hdmi_adj` (Low-Latency-Nachregelung, `vsync_adjust=2`) |
| HDMI-Takt am Pin | DDIO-Ausgang | direkt; Ausgangsregister auf fallender Flanke |
| Analog-VGA, I/O-Board, User-Port, SD-SPI, ADC | vorhanden | gibt es nicht (Eingänge fest belegt) |
| UART/MIDI, ALSA, Interrupts zum HPS | HPS-Peripherie | noch nicht angeschlossen |
| SDRAM | Modul 3,3 V, ein Chip-Select | onboard 128 MB, **1,8 V**, zwei Chip-Selects (`SDRAM_nCS2 = ~SDRAM_nCS`, wie MiSTers 128-MB-Modul; Cores mit 32 MB halten nCS=0) |
| SDRAM-Takt | invertierter Core-Takt über `altddio_out` | PLL-Ausgang mit Phase über `sdram_clk_ddio` (bei 64 MHz +90°, P4) |
| PLLs der Cores | dürfen zur Laufzeit umgestellt werden (`pll_cfg`) | fest — nur `sys` stellt eine PLL um (HDMI) |
| LEDs | high-aktiv | low-aktiv (`LEDR`) |
| Takte 50 MHz | FPGA_CLK1/2/3_50 | CLOCK0/2/1_50 (in dieser Reihenfolge zugeordnet) |

## Stand P1 (erledigt 2026-10-15)

Auf dem Board geprüft: `testpattern.core.rbf` per `p0_switch.py` geladen,
`gp_check.py` liest Kennung und `io_ver` über die Brücke, HDMI zeigt das
Testbild. Wichtig: Nach dem Laden hält `sys_top` den Core im Reset, bis
gp_out[31:30] die Freigabe sieht (macht `gp_check.py`, später Main_MiSTer).
Und: MiSTers Direktvideo bildet DE aus den Syncs nach (für VGA-Adapter); der
HDMI-Sender braucht das echte DE des Cores — in `sys_top_de25.v` geändert.

Nur Direktvideo (`MISTER_DEBUG_NOHDMI`): Das Bild des Cores geht mit seinem
eigenen Takt zum HDMI-Sender. Das taugt nur für Cores mit normgerechtem
Timing — dafür gibt es den Testcore `cores/testpattern` (720p60). Für echte
MiSTer-Cores braucht es den Scaler `ascal` und damit DDR (P3).

## Stand P3: Scaler (Schritt 3, 2026-10-15)

`MISTER_DEBUG_NOHDMI` ist aus: Das Bild des Cores geht über `ascal` und einen
Dreifachpuffer im HPS-DDR (`0xA000_0000`) zum HDMI-Sender. Main schickt das
Ausgangstiming (Befehl `0x20`); Mains Screenshot (`echo screenshot >
/dev/MiSTer_cmd`) liest denselben Puffer. `direct_video=1` wird noch nicht
unterstützt (kein Taktumschalter).

Auf dem Board geprüft: Testbild über den Scaler, OSD per F12 in voller
Größe (doppelt vergrößert), Main misst den Core-Ausgang mit 1280 × 720,
60 Hz, 74,25 MHz. Die HDMI-PLL (`ip/pll_hdmi_de25.ip`) ist noch fest auf
74,25 MHz; die Umschaltung zur Laufzeit folgt in Schritt 4.
`video_debug.v` (Messpunkte der Videokette, 0x2001_4000, lesen mit
`p3/linux/video_debug.py`) bleibt als Werkzeug im Design.

## Stand P3: HDMI-PLL und HDMI-Sender über Main (Schritt 4, 2026-10-16)

**PLL:** Die Agilex-5-IOPLL teilt nur ganzzahlig: Fpix = 50 MHz · M / (N · C).
Main sucht N (1..5, PFD ≥ 10 MHz), M (bis 320) und C so, dass VCO
600..3200 MHz und die Abweichung minimal ist, und schickt die Werte wie
bisher im Cyclone-V-Format. `pll_cfg_de25` übersetzt sie in die Sequenz des
Handbuchs (Clocking and PLL User Guide 813671, Kap. 6.2/6.3): Register
freigeben, Kalibrierstatus löschen, M/N (0x40), Ladungspumpe nach M (0x44),
C0 (0x5C), Reset-Puls (0x80), Kalibrierung erlauben (0x48) und anfordern
(0x88), auf Lock warten. Dauer etwa 1 ms. Auf dem Board gemessen:
1280×720 (74,25 MHz), 1920×1080 (148,5), 1024×768 (65), 640×480 (25,175,
+17 ppm) über `video_mode`, Bild und OSD bei 1080p vom Nutzer bestätigt.

Befunde zum Port der IOPLL (im Handbuch nicht eindeutig, am Board geklärt):
Serienbausteine adressieren Wörter (Byte-Offset >> 2); ein 32-bit-Register
geht als 4 Bytes, LSB zuerst. Schreiben: 10 Takte `write`, 5 × 0x00, dann
b0 b1 b2 b3 b3. Lesen: die Daten kommen ab dem ersten Takt als
`00 b0 b1 b2 b3`, zweimal hintereinander.

**HDMI-Sender:** Main nutzt statt `/dev/i2c-N` den I2C-Master im FPGA
(`linux/main/de25/smbus.cpp`, gleiche Schnittstelle `smbus.h`). Beim ersten
Öffnen übernimmt Main den Bus (`own`); bis dahin stellt `hdmi_config` den
ADV7513 ein, sodass auch ohne Main ein Bild kommt. Main liest Chip-ID und
EDID und schreibt seine eigene Initialisierung.

**Platzierung:** Nur HVIO-IOPLLs haben den Port `core_avl_*`. Welche Art eine
IOPLL wird, entscheidet ihr Referenztakt: CLOCK0_50 (`FPGA_CLK1_50`) liegt in
einer HSIO-Bank und ergibt eine IO96B-PLL. Deshalb hängt `pll_hdmi` an
CLOCK1_50 (`FPGA_CLK3_50`, HVIO) und `pll_audio` an CLOCK0_50 — anders als
bei MiSTer. `pll_audio` ist auf `IOPLL_X63_Y0_N0` festgelegt: In der IO96B-
Bank des HPS-Speichers (X63_Y53) änderte sie den HPS IO hash.

**Nur sys stellt eine PLL um (Regel seit P4):** Der Memtest stellte seine
eigene HVIO-PLL zur Laufzeit um, während `pll_cfg_de25` die HDMI-PLL
einstellte. Zwei gleichzeitig umgestellte HVIO-PLLs stören sich: Schreibzugriffe
gingen verloren, Lesen lieferte falsche Werte, das HDMI-Bild blieb schwarz.
Deshalb haben Cores feste PLLs; eine andere Frequenz ist ein eigener Bau.

**Einlesen statt Lesen-Ändern-Schreiben:** Direkt nach dem Laden antwortet
der Port der IOPLL eine Weile nur mit 0xFF. `pll_cfg_de25` wartet deshalb
nach dem Reset auf Lock und 1 ms (`INIT_DELAY`), liest dann die acht
beteiligten Register (0x10, 0x58, 0x40, 0x44, 0x5C, 0x80, 0x48, 0x88) je
doppelt, bis zwei gleiche Werte kommen, und nimmt 0xFFFFFFFF nie an. Danach
schreibt es nur noch aus diesem gemerkten Stand (fremde Bits bleiben
erhalten), prüft 0x40/0x44/0x5C nach dem Schreiben im ganzen Wort und
wiederholt bei Abweichung nach 1 ms Pause, bis zu 8 Versuche. Statusbit 3 =
Prüffehler, Bits 31:24 = Zahl der Wiederholungen (`p3/linux/pll_cfg.py`).
Am Board: alle Modi sauber, 0 Wiederholungen. Testbench mit Fehlermodell
(verlorene Schreibzugriffe, falsche Lesewerte, „nicht bereit“).

## Stand P3: Core-Wechsel mit DDR-Verkehr (Schritt 5, 2026-10-16)

Wird das FPGA neu geladen, während über F2SDRAM ein Burst läuft oder
Lesedaten unterwegs sind, wartet die HPS-Seite ewig auf den Rest. Auf dem
Agilex 5 hängt dann die SMMU (`arm-smmu-v3 … CMD_SYNC timeout`), mit ihr
alle Geräte mit DMA und schließlich Linux. MiSTer kennt dasselbe Problem auf
dem Cyclone V (`f2sdram_safe_terminator`, dort hängt „nur“ der nächste Core).

`f2s_halt_de25` sitzt zwischen jedem Avalon-Master (ascal, DDRAM des Cores,
ddr_svc) und seinem Port zu `qsys_top`:

- **halt** (von Main, Register `0x2001_7000` Bit 0): den Master an einer
  Befehlsgrenze anhalten — ein angefangener Schreib-Burst läuft zu Ende,
  ein wartender Befehl bleibt stehen, bis er angenommen ist.
- **takeover** (nur ram1, beim System-Reset des Cores): den vom Reset
  abgewürgten Burst selbst zu Ende schreiben (byteenable = 0), wie MiSTers
  Terminator.
- **idle** (Bits 3:1): angehalten, alle Lesedaten zurück, danach 1024 Takte
  Ruhe (Schreibantworten hinter der Clock Crossing Bridge). Ein Port, der
  seit dem Laden nie zugegriffen hat (z. B. ohne Takt), gilt als leer.

Main (`linux/main/de25/fpga_io.cpp`) setzt vor jedem Laden `halt` und wartet
höchstens 0,5 s auf `idle` (gemessen: unter 0,1 ms); sonst lädt es nicht.

**Grenze:** Einen Reset *innerhalb* des Cores sieht `sys` nicht. Bricht ein
Core damit einen DDRAM-Burst ab, hängt Linux trotzdem — so geschehen mit
`ddr_test` im Testpattern-Core (Main setzt `status[0]` beim Start mehrfach).
**Regel für jeden Core:** DDRAM-Bursts auch im Reset zu Ende bringen.

## SDRAM (P4, 2026-10-17)

- **I/O-Register:** Wie bei MiSTer setzt `sys_de25.tcl` `FAST_OUTPUT_REGISTER`
  auf alle `SDRAM_*`, `FAST_OUTPUT_ENABLE_REGISTER` und `FAST_INPUT_REGISTER`
  auf `SDRAM_DQ[*]` sowie `ALLOW_SYNCH_CTRL_USAGE OFF`. MiSTer-Cores haben
  kein I/O-Timing in der `.sdc`, sie verlassen sich auf kurze, gleiche
  Laufzeiten Register↔Pin. Im Fitter-Bericht (Pin-Tabellen, Spalten
  „Input/Output Register“) nachsehen, dass sie gesetzt sind.
- **Daten- und Freigaberegister teilen sich ein Clock-Enable** in der
  I/O-Zelle: Wird das Datenregister nur bei Schreibzugriffen geladen
  (`if (we) dq_out <= …`), das Freigaberegister aber in jedem Takt, findet
  der Fitter keinen Platz (Fehler 14996/24403). Abhilfe: Datenregister in
  jedem Takt laden — am Pin wirkt es nur mit gesetzter Freigabe
  (`cores/memtest/pro/sdram.v`, `cores/menu/pro/sdram.sv`).
- **Takt:** MiSTers invertierter Takt (180°) passt nicht zum 1,8-V-SDRAM des
  DE25 — bei 64 MHz kam fast jeder Lesewert falsch zurück. Fehlerfrei sind
  45–135° (Messungen in `cores/memtest/README.md`). Cores erzeugen
  `SDRAM_CLK` deshalb aus einem eigenen PLL-Ausgang mit Phase und geben ihn
  über `ip/sdram_clk_ddio` (`din = 2'b10`) aus; die passende Phase hängt von
  der Frequenz ab.

## Quartus-Pro-Fallen in MiSTers Code

MiSTer baut mit Quartus Standard. Quartus Pro ist strenger bzw. anders:

| Falle | Wirkung | Abhilfe |
|---|---|---|
| `reg x = 0;` **innerhalb** eines `always`-Blocks (Warnung 16754) | Pro setzt das Register bei jedem Durchlauf zurück. Folgen hier: Videobefehl kam nur in `WIDTH` an (kein HDMI-Signal), OSD unvergrößert | Startwert entfernen (statisch wie unter Quartus Standard) — `sys_top_de25.v`, `pro/osd.v`, `pro/audio_out.sv`, `pro/hps_io.sv` |
| Ausgangsport ohne `reg`, aber in `always` beschrieben | Fehler 13386 | `output reg` — `pro/ddr_svc.sv` |
| boolesche VHDL-Generics als `"false"`/`"true"` | Pro liest die Zeichenkette als Zahl (Fehler 13832) | `1'b0`/`1'b1` — ascal in `sys_top_de25.v` |
| Signale im `generate`-Block, aber außerhalb benutzt | Fehler | auf Modulebene — `pro/hps_io.sv` |
| `inout`-Port (`SDRAM_DQ`) in `always` beschrieben | Fehler 13386 | `inout wire` mit Tri-State `assign DQ = oe ? out : 'z` — `cores/menu/pro/sdram.sv` |
| `altddio_out` (Cyclone-V-Primitive) | Fehler 287078 | für den SDRAM-Takt: PLL-Ausgang mit Phase über `ip/sdram_clk_ddio` (siehe SDRAM oben) — `cores/memtest/pro/memtest.sv`; der Menü-Core nutzt noch `~clk` (er löscht das SDRAM nur) |
| Datenregister mit Clock-Enable an einem `inout` mit I/O-Registern | Fehler 14996/24403 | Datenregister in jedem Takt laden (siehe SDRAM oben) |
| Modulname `pll` im Core | kollidiert mit der PLL im HPS-System | umbenennen (`pll_menu`) — `cores/menu/pro/menu.sv` |
| Bezeichner vor ihrer Deklaration (Warnungen 16746/16749) | Quartus legt ein implizites Netz an; eine spätere Deklaration `wire x = Ausdruck;` gilt als „Startwert“ und wird verworfen — Netz ohne Treiber (Warnung **16788**). Am C64: Laufwerk antwortete nicht | `wire x;` vor die erste Verwendung, Zuweisung als `assign` — `cores/c64`, `sys_top_de25.v` (pal_d/pal_a). Nach jedem Bau 16788 prüfen |
| `static reg x = 0;` im `always`-Block | Warnung 16754 verschwindet, das Register wird trotzdem in jedem Takt zurückgesetzt | nicht nehmen — Register auf Modulebene ziehen |
| Speicher mit zwei Portbreiten, in den beide Ports schreiben | Agilex 5 kann das nicht (altera_syncram: Fehler 272006, auch kein zweiter Takt) — Quartus baut Register | eigene Module mit gleicher Breite (`cores/c64/rtl/`) |
| Zwei-Port-RAM nach Intels Vorlage | „uninferred due to unsupported read-during-write behavior“ (Info 276009) — Register statt M20K | `(* ramstyle = "no_rw_check" *)` |
| `ram_init_file = " "` (Leerzeichen als „keine Datei“) | Quartus Pro stürzt ab (Assertion `required_unc_path_size`) | Inhalt per `$readmemh` nur, wenn eine Datei angegeben ist |
| VHDL-`case` ohne `others`, direkte Instanz ohne `entity` | Fehler 13630 / 13780 | `when others`, `entity work.x` |

**Regel für jede neue MiSTer-Datei und jeden Core:** nach dem ersten Bau im
`*.syn.rpt` nach `Warning (16754)` suchen — Ziel 0. Und nach jedem Bau den
`HPS IO hash` in der Ausgabe von `quartus_pfg` prüfen: `474D6C20…`.

## Bursts über 4-KB-Grenzen (P4, 2026-10-18)

Der C64 (Laufwerk) liest DDRAM in Bursts ab beliebigen Adressen. Ein Burst
über eine 4-KB-Grenze verstößt gegen AXI; über F2SDRAM kam der Teil hinter
der Grenze verfälscht an (am Board: genau die Disketten-Sektoren über einer
4-KB-Grenze lasen fehlerhaft). Platform Designer teilt solche Bursts nicht
selbst auf, und die Avalon-Bridges haben dafür keine Einstellung. Daher
sitzt in `sysmem_de25` hinter jedem `f2s_halt_de25` ein `avl_burst_4k`:
Lesebefehle über eine Grenze werden zu zwei Befehlen, Schreib-Bursts
beginnen an der Grenze einen neuen Burst; ohne Grenze geht alles unverändert
und ohne Zusatztakt durch (Testbench `tb/tb_avl_burst_4k.v`).

## Lesen immer mit allen Bytes (P5, 2026-10-22)

MiSTer-Cores setzen `DDRAM_BE` oft nur beim Schreiben; beim Lesen bleibt der
Wert des letzten Schreibzugriffs stehen (z486 `main_memory`). Der DE10-Nano
ignoriert byteenable beim Lesen. Platform Designer macht daraus aber einen
schmalen AXI-Lesezugriff: Über F2SDRAM kamen **nur die freigegebenen Bytes**
zurück, der Rest war 0 (am Board beim Briefkasten des z486: geschrieben
`44434241`, gelesen `00004200`). `sysmem_de25` gibt deshalb für ram1/ram2 beim
Lesen immer `byteenable = FF` weiter (`tb/tb_sysmem_de25.v` prüft es).
Teil-Schreibzugriffe (wstrb) funktionieren dagegen korrekt.

Zur Fehlersuche hat sich bewährt (nicht im Repo): Verilator-Simulation des
Cores mit DDR-Protokoll; ein vorübergehender Mitschreiber in `sysmem`, der
Core- und F2SDRAM-Seite aufzeichnet und das Protokoll über den freien Port
ram2 ins DDR schreibt (Auslesen mit Python über `/dev/mem`). Über JTAG sind
im HPS-first-Betrieb keine SLD-Knoten sichtbar (`jtagconfig -n` leer), also
weder Signal Tap noch In-System Memory Content Editor. Der Systemcache des
CCU (DMI-SMC) war unschuldig.

## Screenshot im Framebuffer-Modus (P5, 2026-10-22)

Mains Screenshot liest den Puffer des Scalers. Zeigt ein Core seinen
Framebuffer (`MISTER_FB`, z. B. z486 in SVGA-Modi), steht dort nur der
VGA-Eingang des Cores. Main liest das Bild deshalb direkt aus dem DDR
(Patch 0010). Die Palette bei 8 bpp kennt nur der Scaler; `sys_top_de25`
führt deshalb eine **Schattenkopie** (256 × 24 bit, 1 M20K, geschrieben mit
den `FB_PAL_*`-Signalen des Cores) und liefert sie über den neuen
UIO-Befehl **`0x4E`** (MiSTer belegt ihn nicht): erste Antwort `0x8000 |`
Anzahl Paletten-Schreibzugriffe (Diagnose), danach je Eintrag zwei Wörter
(G/B, dann R).

## Schlankes HPS-System (P5, 2026-10-18)

Terasics GHRD bringt Demo- und Debug-Teile mit, die MiSTer nicht braucht und
die im FPGA viel Platz belegten (Menü-Core: 22 010 ALMs, 190 M20K, davon das
Menü selbst nur ~800 ALMs). Für den z486 (PC allein ~25 700 ALMs, 209 M20K)
entfernt `hps_slim.tcl` sie:

| Teil | Zweck im GHRD | Belegung |
|---|---|---|
| `ocm` | 256 KB On-Chip-RAM an `hps2fpga` | 128 M20K |
| `subsys_debug` | drei JTAG-Master (System Console) | ~1 200 ALMs |
| ACE5-Lite-Übersetzer + Bus | nur für den JTAG-Master zum HPS-Speicher | ~2 600 ALMs |
| `ext_hps_f2sdram_master` | Fenster des JTAG-Masters zum F2SDRAM | – |
| FPGA→HPS-Bridge (`f2s_data_width 0` im HPS-IP) | ohne Gegenstelle verlangt Quartus eine Verbindung (24265/129015); fest beschaltete Eingänge genügen nicht | – |

Ergebnis Menü-Core: **13 735 ALMs, 59 M20K** (−8 275 / −131), HPS IO hash
unverändert (`474D6C20…`, auch mit abgeschalteter FPGA→HPS-Bridge), am Board
Wechsel Menü ↔ C64 ohne Auffälligkeiten. Was bleibt: LW-Bridge mit
`subsys_periph`, F2SDRAM mit den drei DDR-Ports, `hps2fpga` (unbenutzt, darf
offen bleiben). Ohne JTAG-Master gehen Tests per System Console nicht mehr —
Signal Tap schon; für eine Debug-Variante `fetch_hps.py` ohne
`hps_slim.tcl` laufen lassen.

**Falle:** Quartus Pro erzeugt `qsys_top` beim Core-Bau nicht neu, wenn sich
die `.qsys` geändert hat — der Bau nimmt dann das alte `qsys_top/synth/
qsys_top.v` (Fehler „undefined entity ocm“). `fetch_hps.py` ruft deshalb
am Ende `qsys-generate` auf (mit `--search-path=custom_ip/**/*,$`, sonst
fehlt `f2sdram_adapter`).

## Prüfen

- Testbenches: `tb/tb_hps_gp_bridge.v`, `tb/tb_hdmi_config.v`,
  `tb/tb_sysmem_de25.v`, `tb/tb_video_debug.v`, `tb/tb_testpattern.v`,
  `tb/tb_pll_cfg_de25.v` (mit Modell `tb/hvio_pll_model.v`),
  `tb/tb_i2c_master_de25.v` (Modell `tb/i2c_smbus_model.v`),
  `tb/tb_avl_slow_cdc.v`, `tb/tb_f2s_halt_de25.v` (`python tb/run_sim.py`).
- `sys_top_de25` als Ganzes nur in Quartus: MiSTers Quellen benutzen
  Bezeichner vor ihrer Deklaration — Quartus nimmt das hin, Questa nicht.
- Auf dem Board: `linux/tools/gp_check.py` liest die Kennung über die Brücke;
  `p3/linux/pll_cfg.py` (PLL-Register lesen, umstellen: `mhz 108`),
  `p3/linux/i2c_test.py` (ADV7513-Kennung lesen; Main vorher stoppen),
  `p3/linux/f2s_halt.py` (DDR-Sperre lesen, setzen, aufheben).
- Python-Werkzeuge greifen über `ctypes` mit echten 32-bit-Zugriffen auf
  `/dev/mem` zu: `struct.pack_into` auf dem mmap zerfiel in Teilzugriffe, der
  I2C-Master sah dann nur das unterste Byte des Befehls.
