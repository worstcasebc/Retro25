# P3 — F2SDRAM, Scaler, Menü-Core

Ziel: Core-Auswahl über F12 wie beim MiSTer. Plan und Entscheidungen
(2026-10-15) in `docs/roadmap.md`:

- **Anbindung:** drei Avalon-Ports (vbuf 128 bit, ram1/ram2 64 bit) in
  `qsys_top` exportieren; Platform Designer erzeugt Arbiter, Breiten-
  anpassung, Taktübergang und den Weg zum AXI4-F2SDRAM (256 bit, 100 MHz).
  Das harte HPS-IP bleibt unverändert.
- **DDR-Fenster:** obere 512 MB `0xA000_0000–0xBFFF_FFFF`; FPGA-Adresse
  `0x2000_0000` (MiSTer) + Bit 31. Reservierung per `fdt` im U-Boot-Skript.
- **Reihenfolge:** 1 Adressmodell prüfen · 2 Ports + Speichertest ·
  3 ascal mit fester 720p-PLL · 4 HDMI-PLL-Rekonfiguration + ADV7513 über
  Main · 5 Menü-Core.

## Schritt 1 — Adressmodell und Kohärenz (ohne neues RTL)

Das GHRD hat schon einen JTAG-Master auf F2SDRAM (`hps_f2sdram` →
`ext_hps_f2sdram_master`, 4-GB-Fenster ab 0 → `f2sdram_adapter`, AxCACHE=2).
Er steckt in jedem Kern mit `qsys_top`, also auch im Testcore.

Weil das spätere Fenster heute noch Linux gehört, testen wir an eigenen,
festgenagelten Seiten eines Linux-Prozesses:

1. Board: `sudo python3 ~/p3/f2sdram_probe.py` — zeigt physische Adressen,
   die erwarteten Werte und die System-Console-Befehle, dann wartet es.
2. PC: Quartus → Tools → System Debugging Tools → **System Console**:
   ```
   source Q:/p3/sc/f2sdram.tcl
   f2s_scan  0x…  3       ;# mit allen drei Mastern lesen: wer ist wer?
   f2s_open  <Nummer>
   f2s_read  0x…  2       ;# Adressen aus Schritt 1
   f2s_write 0x…  0xCAFE0001
   ```
3. Board: Enter — das Skript meldet, ob der Schreibwert sofort oder erst
   nach dem Verdrängen aus dem Cache sichtbar ist.
4. Streng: `sudo python3 f2sdram_probe.py --spin` liest ohne Pause, während
   System Console schreibt (Main vorher anhalten, es teilt sich den Kern).

| Frage | Ergebnis (2026-10-15) |
|---|---|
| Sieht das FPGA physische Adressen? | **Ja.** Beide 4-GB-JTAG-Master (`phy_1`, `phy_2` = `hps_m` über F2H und `hps_f2sdram`) lesen das Muster unter der physischen Adresse aus `/proc/self/pagemap`, ohne Versatz. `phy_0` (`fpga_m`) liefert 0. Für P3: FPGA-Adresse = physische Adresse, `0xA000_0000` liegt direkt auf `0xA000_0000`. |
| Kommt FPGA-Schreiben ohne Cache-Pflege bei der CPU an? | **Ja, über beide Wege.** Strenger Test (`--spin`): Ein Kern (CPU 3, Main angehalten) liest zwei Stellen ununterbrochen, die Zeilen bleiben also im L1. Die JTAG-Schreibzugriffe von `phy_1` und `phy_2` sah er trotzdem sofort. Die Hardware hält die Caches kohärent, auch auf dem F2SDRAM-Weg mit AxCACHE=2. Welcher `phy_N` F2SDRAM ist, bleibt offen (ohne verknüpftes Design namenlos); bei gleichem Verhalten unerheblich. |

System Console geht auch ohne GUI (so lief der strenge Test):
`(sleep 60 | system-console.exe --cli --script=… )`. stdin muss offen
bleiben, sonst beendet sich die Konsole vorzeitig. Direkt nach dem Start
ist die Suche nach JTAG-Mastern noch unvollständig, deshalb warten, bis alle
drei da sind.

## Schritt 2a — DDR-Fenster reservieren (erledigt 2026-10-15)

`linux/boot/retro25-bootscr.sh install <start.core.rbf>` (Nachfolger von
`p0/linux/p0_bootscr.sh`) ergänzt Terasics U-Boot-Skript: Start-Core laden
und nach dem Laden des Device Tree per `fdt` einen Knoten
`/reserved-memory/retro25_fpga@a0000000` (512 MB, `no-map`) anlegen.

- Falle: `booti` verschiebt den Device Tree sonst ans RAM-Ende
  (`0xBEAD2000`, mitten ins Fenster), der Kernel meldet dann „failed to
  reserve memory“ → `setenv fdt_high 0xffffffffffffffff` hält ihn an der
  Ladeadresse `0x86000000`.
- Ergebnis: Kernel meldet `0xa0000000..0xbfffffff nomap non-reusable
  retro25_fpga@a0000000`; System RAM nur noch `0x8200_0000–0x9FFF_FFFF`,
  `free`: 424 MB (vorher 934); CMA weicht nach `0x9CC0_0000` aus.
  `/dev/mem` erlaubt Lesen/Schreiben im Fenster (geprüft an `0xA000_0000`,
  `0xB000_0000`, `0xBFFF_F000`). Main läuft unverändert.

## Schritt 2b/2c — DDR-Ports und Speichertest (erledigt 2026-10-15)

- **Platform Designer:** `sys/de25/hps_f2sdram_ports.tcl` legt in
  `qsys_top` drei Avalon-MM Clock Crossing Bridges an (`f2s_vbuf` 128 bit,
  `f2s_ram1`/`f2s_ram2` 64 bit; 32-bit-Byte-Adressen, Bursts bis 128,
  FIFOs 256). Jede bekommt vorn eine Clock Bridge mit exportiertem
  Eingang — ein direkt exportierter Takteingang gilt nicht als Taktquelle,
  dann fehlt dem Reset-Synchronizer der Takt (Fehler in `qsys-generate`).
  `tools/fetch_hps.py` wendet das Skript beim Holen nach `sys/hps`
  automatisch an (Wegwerf-Projekt im Temp-Ordner, weil qsys-script
  IP-Dateien ins angegebene Projekt einträgt). Mehrfaches Anwenden auf
  schon umgebaute Dateien vermeiden (Instanzen heißen dann `…_0`).
- **RTL:** `sysmem_de25` reicht die Ports durch und legt jede Adresse ins
  Fenster (`{3'b101, Byte[28:0]}`); `sys_top_de25` verbindet mit
  `qsys_top`, vbuf ist im Direktvideo-Betrieb fest auf 0.
  Testbenches `tb_sysmem_de25`, `tb_ddr_test`.
- **Testcore:** `ddr_test` schreibt nach dem Reset (und per OSD) 128 KB
  ab MiSTer-Adresse `0x3000_0000`, liest zurück, Ergebnis als Feld am
  linken Rand. Gegenprobe: `sudo python3 p3/linux/ddr_check.py`.
- **Bau:** HPS IO hash unverändert (`474D6C20…`), Timing erfüllt
  (Setup ≥ 3,3 ns), 13 058 ALMs (+2 540 für Bridges und Interconnect),
  138 RAM-Blöcke (+5).
- **Board:** Feld grün (FPGA liest sein Muster fehlerfrei zurück); Linux
  liest an `0xB000_0000` 16 384 Wörter fehlerfrei, nach erneutem Start per
  OSD mit neuem seed — der FPGA→DDR→Linux-Weg funktioniert.

## Schritt 3 — ascal mit fester 720p-PLL (erledigt 2026-10-15)

- Scaler aktiv (`MISTER_DEBUG_NOHDMI` aus), Dreifachpuffer im DDR-Fenster,
  feste HDMI-PLL. Hauptfehler war die Quartus-Pro-Falle 16754 (lokale
  `reg x = 0;` in `always`-Blöcken werden bei jedem Durchlauf
  zurückgesetzt), Details in `sys/de25/README.md`.
- Werkzeug: `p3/linux/video_debug.py` liest die Messpunkte der Videokette
  (`sys/de25/video_debug.v`, `0x2001_4000`).

## Schritt 4 — HDMI-PLL zur Laufzeit, ADV7513 über Main (erledigt 2026-10-16)

- **Entschieden (2026-10-15):** Das FPGA übersetzt Mains PLL-Register
  (Cyclone-V-Format) in die Agilex-Sequenz (`sys/de25/pll_cfg_de25.v`); Main
  rechnet nur ganzzahlig (`linux/main/patches/0004-…`). Eigener I2C-Master
  im FPGA (`sys/de25/i2c_master_de25.v`), Main bekommt ein Ersatz-
  `smbus.cpp` (`linux/main/de25/`). Linux erreicht beides über `disk_m0`
  (`0x2001_5000` PLL-Debug, `0x2001_6000` I2C; `avl_slow_cdc` für den
  Taktübergang).
- **Board:** Main stellt bei `video_mode` 0/1/6/8 die PLL um (74,25 / 65 /
  25,175 / 148,5 MHz, gemessen mit `video_debug.py`), Lock nach ~1 ms, keine
  Timeouts. Main öffnet den ADV7513 (0x39, EDID 0x3F, SPD 0x38) und liest
  das EDID. 1080p mit Bild und OSD vom Nutzer bestätigt.
- **Fallen:** nur HVIO-IOPLLs haben den Umkonfigurations-Port, und der
  Referenztakt bestimmt die Art (CLOCK1_50 ist HVIO, CLOCK0_50 HSIO);
  `pll_audio` darf nicht in die IO96B-Bank des HPS-Speichers (HPS IO hash).
  Python-Zugriffe auf `/dev/mem` mit `ctypes` (echte 32-bit-Zugriffe).
- Werkzeuge: `p3/linux/pll_cfg.py` (PLL lesen/umstellen),
  `p3/linux/i2c_test.py` (ADV7513 lesen, Main vorher stoppen).
- **Offen:** `vsync_adjust=2` (Low-Latency, braucht fraktionale PLL),
  `direct_video`.

## Schritt 5 — Menü-Core, Core-Auswahl per F12 (erledigt 2026-10-16)

- **Entschieden (2026-10-16):** MiSTers Menu_MiSTer übernehmen
  (`tools/fetch_menu.py`, Commit `fa83dc1`, `cores/menu/vendor/`); Cores
  liegen wie bei MiSTer in Ordnern unter `/media/fat` (`_Retro25/`), der
  Menü-Core als `/media/fat/menu.rbf` (`install.sh` legt ihn dort ab).
- Anpassungen für Quartus Pro in `cores/menu/pro/` (Diff je `*.patch`):
  `pll` → `pll_menu` (der Name `pll` ist im HPS-System vergeben), Startwerte
  aus `always`-Blöcken (Falle 16754), `SDRAM_DQ` als `inout wire` mit
  Tri-State, `altddio_out` durch `assign SDRAM_CLK = ~clk` ersetzt.
- **Board:** Menü als Start-Core (Rausch-Hintergrund, OSD mit Core-Liste),
  Testpattern per F12 laden und zurück ins Menü — vom Nutzer bestätigt;
  20 Wechsel Menü ↔ Testpattern über Main ohne Fehler.
- **Fehlersuche Core-Wechsel** (Linux hing: `arm-smmu-v3 … CMD_SYNC timeout`):
  1. Das FPGA darf nie mitten in einem F2SDRAM-Zugriff neu geladen werden —
     die HPS-Seite wartet dann ewig auf den Rest des Bursts bzw. auf die
     Abnahme der Lesedaten, die SMMU hängt und mit ihr ganz Linux. Neu:
     `sys/de25/f2s_halt_de25.v` vor jedem DDR-Port (Gegenstück zu MiSTers
     `f2sdram_safe_terminator`); Main hält vor dem Laden alle Ports an und
     wartet auf „leer“ (Register `0x2001_7000`, Werkzeug
     `p3/linux/f2s_halt.py`).
  2. Der eigentliche Auslöser war aber `cores/testpattern/ddr_test.v`: Ein
     Reset **innerhalb** des Cores (Main setzt `status[0]` beim Start
     mehrfach) brach einen Schreib-Burst ab. Den sieht die Sperre in sys
     nicht. Jetzt schreibt `ddr_test` einen angefangenen Burst auch im
     Reset zu Ende. **Regel für jeden Core:** einen DDRAM-Burst nie per
     Reset abbrechen.
  3. „Board tot“ war zweimal nur das Netz: Der USB-WLAN-Stick fällt beim
     Umladen aus (bekannt aus P0). Das Board hängt jetzt am Ethernet.
- **Nebenwirkung:** Die vielen harten Resets haben das Root-Dateisystem der
  SD-Karte beschädigt (Superblock, 16 Programme in `/usr/bin`). Gerettet mit
  `tools/sd_rescue.py` (Abbild unter Windows) und `e2fsck`/`debugfs` in
  Docker; daraus der Schritt P3a (schreibgeschütztes Root) in
  `docs/roadmap.md`.
- **Offen:** `vsync_adjust=2`, `direct_video`, `shmem_map(0x1FF00000)`
  außerhalb des Fensters; SDRAM des Menüs nur Größenerkennung, Takt direkt
  invertiert statt DDIO.
