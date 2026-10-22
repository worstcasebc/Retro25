# Retro25 — MiSTer auf dem Terasic DE25-Nano

Retro25 bringt das [MiSTer](https://github.com/MiSTer-devel)-Framework auf das
**Terasic DE25-Nano** (Intel/Altera Agilex 5 E, Arm-HPS mit Linux). Wie beim
MiSTer lädt Linux zur Laufzeit verschiedene FPGA-Cores, ausgewählt über das
Menü (F12). Portiert sind das Framework `sys/` (HDMI, OSD, Scaler, Audio,
`hps_io`), das Linux-Programm Main_MiSTer (jetzt aarch64) und bisher drei
Cores: Menü, **C64** und **z486** (486-PC).

> Lernprojekt eines Einzelnen, kein offizieller MiSTer-Port. Alles hier lief
> auf genau einem Board; rechne mit Ecken und Kanten.

## Stand (2026-10-22)

| Teil | Stand |
|---|---|
| Boot HPS-first, Core-Wechsel aus Linux (~2 s) | ✔ 30+ Wechsel ohne Fehler |
| `sys/`: HDMI (ADV7513), Scaler `ascal`, OSD, Audio, Videomodi, DDR über F2SDRAM | ✔ |
| Main_MiSTer (aarch64): Menü, USB-Tastatur/-Maus/-Gamepads, Disk-Images, Screenshots | ✔ |
| Menü-Core, Core-Auswahl über F12 | ✔ |
| **C64** (C64_MiSTer): BASIC, PRG, D64 lesen/schreiben, CRT, TAP, SID, Joysticks | ✔ → [`cores/c64/README.md`](cores/c64/README.md) |
| **z486** (z486_MiSTer): FreeDOS, Windows 95, Doom, Quake, SVGA, x87, Sound Blaster | ✔ → [`cores/z486/README.md`](cores/z486/README.md) |
| Schreibgeschütztes Linux-Root (SD-Karte übersteht harte Resets) | ✔ |
| `vsync_adjust=2`, `direct_video`, ALSA-Ausgabe, MIDI | offen |

Meilensteine und Entscheidungen: [`docs/roadmap.md`](docs/roadmap.md);
Einzelheiten zum Port: [`sys/de25/README.md`](sys/de25/README.md),
[`linux/main/README.md`](linux/main/README.md),
[`linux/system/README.md`](linux/system/README.md).

### Wie es zusammenhängt

```
 Linux (HPS, Cortex-A76/A55)                 FPGA (Agilex 5)
 ┌──────────────────────────┐  LW-Bridge  ┌───────────────────────────────┐
 │ Main_MiSTer (aarch64)    │◄───────────►│ sys/ (für alle Cores gleich): │
 │  Menü, Eingabe, Disks    │ gp_out/gp_in│  HDMI, OSD, Scaler, Audio,    │
 │  Core laden per Overlay  │             │  hps_io  └─ emu (der Core)    │
 └──────────────────────────┘  F2SDRAM ◄──┴───────────────────────────────┘
        ▲ SD-Karte: Linux, Cores, Spiele        DDR des HPS: Scaler, Disks
```

Analogie: Das Board ist eine Spielkonsole mit Wechselmodulen. Linux ist der
Hausmeister, der die Module (Cores) einsteckt; `sys/` ist die immer gleiche
Steckerleiste, an der jedes Modul Bildschirm, Ton und Tastatur findet.

Unterschiede zum DE10-Nano-MiSTer: Das Board bootet **HPS-first** — im
QSPI-Flash liegen nur I/O-Ring und Bootloader, U-Boot lädt den Start-Core von
der SD-Karte, Linux wechselt ihn per Device-Tree-Overlay. Der SDRAM (128 MB)
ist fest auf dem Board, Linux ist Terasics Ubuntu 22.04 statt MiSTer-Linux.

---

## Was nicht im Repository liegt (und warum)

Retro25 selbst steht unter **GPL-3.0-or-later** ([`LICENSE`](LICENSE)). Nicht
enthalten ist alles, was wir nicht weitergeben dürfen oder sollten:

| Teil | Warum nicht | Woher |
|---|---|---|
| MiSTer `sys/`, Main_MiSTer, Menu/C64/MemTest-Cores | Fremdcode; teils ohne Lizenzvermerk je Datei | `tools/setup.py` holt sie aus festen Commits |
| z486_MiSTer | ohne Lizenzdatei; Microcode ausdrücklich nicht Apache-2.0 | `tools/setup.py` |
| Terasic-GHRD (HPS-System, Bootloader-SPL) | Terasic erlaubt die Nutzung, nicht die Weitergabe | Terasic-Ressourcenpaket, `tools/fetch_hps.py` |
| C64- und 1541-ROMs | urheberrechtlich geschützt | selbst beschaffen → `roms/` |
| Gebaute Bitstreams (`.rbf`, `.jic`) | enthalten ROMs bzw. den z486-Microcode | selbst bauen |

Im Repository liegen dafür die eigenen Teile (`sys/de25/`, `linux/`,
`tools/`, `tb/`, Core-Rahmen) und die Änderungen am Fremdcode als
**Patches** (`*.patch` in `pro/`) bzw. als Textersetzungen
(`cores/z486/make_pro.py`). `tools/setup.py` holt den Fremdcode nach
`vendor/` und erzeugt daraus die angepassten Kopien in `pro/`.

---

## Installation Schritt für Schritt

Die Anleitung geht von einem neuen DE25-Nano und einem Windows-PC aus.
Rechne für den ersten Durchgang mit einem Nachmittag (davon ~1 h Quartus-Bau).
Befehle mit `>` laufen in der Windows-Eingabeaufforderung, mit `$` auf dem
Board (per SSH oder serieller Konsole).

### 1. Was du brauchst

**Hardware**
- Terasic DE25-Nano mit Netzteil
- microSD-Karte, **mindestens 16 GB** (getestet: 32 GB)
- USB-Kabel zum PC (der Onboard-USB-Blaster und die serielle Konsole hängen
  an derselben USB-Buchse)
- HDMI-Monitor, USB-Tastatur (über USB-C-Adapter/-Hub am USB-Host-Port)
- **Netzwerkkabel** — ein USB-WLAN-Stick verliert bei jedem Core-Wechsel die
  Verbindung
- optional: USB-Gamepad, USB-Maus, USB-Stick für Spiele

**Software auf dem PC**
- **Quartus Prime Pro 26.1** mit Geräteunterstützung *Agilex 5* (die freie
  Lite/Standard-Edition kann Agilex 5 nicht). Der Installer setzt die
  Umgebungsvariable `QUARTUS_ROOTDIR`; prüfen: `> echo %QUARTUS_ROOTDIR%`.
- **Python 3.10+** und **git** (beide im `PATH`)
- **Docker Desktop** (baut Main_MiSTer in einem arm64-Ubuntu-Container)
- ein Programm zum Schreiben von SD-Abbildern (balenaEtcher, Win32DiskImager
  oder Rufus) und ein Terminal für die serielle Konsole (PuTTY o. ä.)

**Von Terasic** ([terasic.com](https://www.terasic.com.tw) → DE25-Nano →
Resources), zwei Downloads:
- das **Linux-SD-Abbild** `de25_nano_sdcard_console_v1.1`
  (`de25_nano_revA_sdcard_console_v1.1.img`, Ubuntu 22.04, Linux 6.12)
- das **Ressourcenpaket** („DE25-Nano resource package“, CD-Inhalt) — daraus
  braucht Retro25 das GHRD unter `Demonstration\SoC_FPGA\GHRD`

### 2. Repository holen und Fremdcode einrichten (PC)

```
> git clone <URL dieses Repositorys> C:\Retro25
> cd C:\Retro25
> python tools\setup.py
```

`setup.py` holt MiSTer-Framework, Main_MiSTer, Menü, C64, MemTest und z486
(je fester Commit, per `git`), dazu die z486-Boot-ROMs und FreeDOS-Testplatte,
und erzeugt die angepassten Kopien. Am Ende listet es, was noch fehlt. Mit
`python tools\setup.py --check` lässt sich das jederzeit prüfen.

**Kurzer Pfad (wichtig):** Quartus bricht HPS-Designs in tief verschachtelten
Ordnern nach ~40 s ab (`dni::save_checkpoint … manifest.txt`). Deshalb das
Repository als Laufwerk `Q:` einbinden und **alle Quartus-Schritte über
`Q:\`** starten:

```
> subst Q: C:\Retro25
```

`subst` gilt bis zum nächsten Windows-Neustart, dann erneut ausführen.

### 3. HPS-System aus Terasics GHRD erzeugen (PC)

Das Ressourcenpaket entpacken, dann:

```
> python tools\fetch_hps.py <Ressourcenpaket>\Demonstration\SoC_FPGA\GHRD sys\hps
```

Das Skript kopiert das HPS-System nach `sys/hps/` und baut es mit
Platform Designer (per `qsys-script`) für Retro25 um:
- `sys/de25/hps_bridges.tcl` — zwei Avalon-Brücken an der LW-Bridge für die
  Register von Main (gp_out/gp_in, PLL, I2C, DDR-Sperre)
- `sys/de25/hps_f2sdram_ports.tcl` — drei DDR-Ports für Scaler und Cores
- `sys/de25/hps_slim.tcl` — Demo- und Debug-Teile raus (Platz für den z486)

Dauer ~5 min. Endet es mit „qsys_top neu erzeugt.", ist alles gut.

### 4. Cores bauen (PC)

C64-ROMs vorher nach `roms/` legen (Dateinamen in
[`roms/README.md`](roms/README.md)). Dann je Core:

```
> python tools\make_core_qsf.py menu
> Q:\tools\build_core.bat menu                 :: ~10 min

> python tools\make_c64_roms.py
> python tools\make_core_qsf.py c64
> Q:\tools\build_core.bat c64                  :: ~15 min

> python tools\make_core_qsf.py z486
> Q:\tools\build_core.bat z486                 :: ~20 min
```

Ergebnis: `cores\<core>\quartus\output_files\<core>.core.rbf`.
`build_core.bat` zeigt am Ende die Zeilen mit „hash“ — der **HPS IO hash**
muss bei allen Cores gleich sein (sonst passt der Core nicht zum Flash).

Flash-Datei (I/O-Ring + HPS-Bootloader) aus dem Menü-Core:

```
> Q:\tools\make_flash.bat menu                 :: -> menu.hps.jic
```

Main_MiSTer (Docker Desktop muss laufen; der erste Bau dauert wegen der
arm64-Emulation ~15 min):

```
> python tools\build_main.py                   :: -> linux\main\build\MiSTer
```

### 5. SD-Karte schreiben und erster Start

1. `de25_nano_revA_sdcard_console_v1.1.img` mit balenaEtcher o. ä. auf die
   microSD-Karte schreiben, Karte ins Board.
2. Board per USB-C mit dem PC verbinden. Im Geräte-Manager erscheinen
   **zwei** serielle Ports: einer führt ins FPGA, der andere ist die
   Linux-Konsole (beim Entwickler `COM11`; im Zweifel beide ausprobieren).
   Terminal öffnen: **115200 Baud, 8N1**, keine Flusskontrolle.
3. Netzwerkkabel stecken, Board einschalten. Auf der Konsole bootet Linux;
   Anmeldung **`terasic` / `123`**.
4. IP-Adresse nachsehen: `$ ip -4 addr show eth0` (bzw. die Verbindung, die
   eine Adresse hat). Ab jetzt geht alles auch per SSH:
   `> ssh terasic@<board-ip>`.

Tipp: Damit das Board im Router immer dieselbe Adresse bekommt, eine feste
MAC setzen (Name der Verbindung aus `nmcli con show`):
`$ sudo nmcli con modify "Wired connection 1" 802-3-ethernet.cloned-mac-address <MAC>`
und im Router reservieren.

### 6. Pakete installieren (Board)

```
$ sudo apt update
$ sudo apt install device-tree-compiler u-boot-tools libimlib2
```

(`dtc` baut das Overlay zum Core-Laden, `mkimage` das U-Boot-Skript,
`libimlib2` braucht Main für Screenshots und Hintergrundbilder.)

### 7. SD-Karte aufteilen (Board)

Terasics Abbild hat eine 300-MB-Bootpartition (FAT) und eine 3,4-GB-Root
(fast voll). Retro25 braucht:

| Partition | Größe | Inhalt |
|---|---|---|
| `mmcblk0p1` | 300 MB FAT | Bootloader, Kernel, Start-Core (`retro25/core.rbf`) |
| `mmcblk0p2` | 8 GiB ext4 | Linux, später **schreibgeschützt** |
| `mmcblk0p3` | Rest, ext4, Label `retro25data` | `/media/fat`: Main, Cores, Spiele, Einstellungen |

Warum? Ein Reset mitten im Schreiben zerstört ein Dateisystem. Das Linux-Root
wird deshalb schreibgeschützt eingehängt; alles, was sich ändert, liegt auf
der eigenen Datenpartition (wie beim MiSTer `/media/fat`).

Vorher Partitionstabelle sichern, dann Root auf 8 GiB vergrößern (Start
bleibt bei Sektor 616449) und eine dritte Partition anhängen:

```
$ sudo sfdisk -d /dev/mmcblk0 > ~/mmcblk0-partitionen.txt
$ echo '616449,16777216' | sudo sfdisk --no-reread -N 2 /dev/mmcblk0
$ echo ',,L' | sudo sfdisk --no-reread --append /dev/mmcblk0
$ sudo reboot
```

Nach dem Neustart Root-Dateisystem vergrößern und Datenpartition anlegen:

```
$ sudo resize2fs /dev/mmcblk0p2
$ sudo mkfs.ext4 -L retro25data /dev/mmcblk0p3
$ sudo mkdir -p /media/fat && sudo mount /dev/mmcblk0p3 /media/fat
$ sudo mkdir /media/fat/retro25 && sudo chown terasic:terasic /media/fat/retro25
$ ln -s /media/fat/retro25 ~/retro25
$ lsblk                                  # p2 ~8G, p3 = Rest
```

`~/retro25` ist der Arbeitsordner für alles, was vom PC kommt; er liegt auf
der Datenpartition, damit er auch bei schreibgeschütztem Root beschreibbar
ist.

> Diese Befehle sind die Kurzfassung dessen, was auf dem Entwicklerboard in
> zwei Etappen geschah (P0: Root vergrößert, P3a: Datenpartition). Meldet
> `sfdisk`, das Gerät sei belegt, hilft zusätzlich `--force`. Bei Problemen:
> Karte neu beschreiben und von vorn — es ist noch nichts verloren.

### 8. Dateien aufs Board kopieren (PC)

```
> scp -r linux\system linux\boot terasic@<board-ip>:~/retro25/
> scp cores\menu\quartus\output_files\menu.core.rbf terasic@<board-ip>:~/retro25/
> scp cores\c64\quartus\output_files\c64.core.rbf terasic@<board-ip>:~/retro25/
> scp cores\z486\quartus\output_files\z486.core.rbf terasic@<board-ip>:~/retro25/
> python tools\build_main.py --deploy terasic@<board-ip>
```

`--deploy` kopiert Main (`MiSTer`), `install.sh`, `MiSTer.ini` und `board/`
nach `~/retro25/`.

### 9. Systemeinstellungen (Board)

```
$ cd ~/retro25/system && sudo ./install.sh
$ sudo reboot
```

Danach: Root schreibgeschützt, `/media/fat` = Datenpartition, Logs und
Journal im RAM, USB-Sticks erscheinen unter `/media/usb0…5`, Magic SysRq frei.
Prüfen: `$ findmnt /media/fat` zeigt `/dev/mmcblk0p3`. Für Wartung (z. B.
`apt`) das Root kurz beschreibbar machen: `sudo retro25-rw` … `sudo retro25-ro`.

### 10. Bootskript und Flash (Board, dann PC)

Erst das U-Boot-Skript erweitern — es lädt künftig den Menü-Core beim
Einschalten ins FPGA und reserviert 512 MB DDR für das FPGA:

```
$ cd ~/retro25
$ sudo bash boot/retro25-bootscr.sh install menu.core.rbf
$ sudo poweroff
```

Dann das QSPI-Flash beschreiben (HPS-first):

1. Board **stromlos**, Schalter **SW5 in den AS-Modus**: SW5.1 OFF,
   SW5.2 ON, SW5.3 ON (Auslieferungszustand). SW5 nur stromlos umstellen.
2. Board einschalten (USB zum PC steckt), dann am PC:
   ```
   > Q:\tools\flash.bat menu
   ```
3. Board aus- und wieder einschalten.

Auf der seriellen Konsole erscheint jetzt `Retro25: lade retro25/core.rbf
ins FPGA`, danach bootet Linux wie gewohnt. Kontrolle nach dem Anmelden:
`$ ls /proc/device-tree/reserved-memory/` zeigt `retro25_fpga@a0000000`.

> Getestet ist dieser Schritt mit dem `.jic` aus dem P0-Versuch
> (`p0\quartus\build_p0.bat`, gleiches HPS-System, gleicher HPS IO hash);
> `make_flash.bat` erzeugt dieselbe Art Datei aus dem Menü-Core.

### 11. Main_MiSTer einrichten (Board)

```
$ cd ~/retro25
$ sudo ./install.sh menu.core.rbf c64.core.rbf z486.core.rbf
```

Das richtet ein: Main unter `/media/fat/MiSTer`, `MiSTer.ini`, Menü als
`/media/fat/menu.rbf`, die übrigen Cores als `/media/fat/_Retro25/C64.rbf`
und `Z486.rbf`, das Overlay zum Core-Laden und den Dienst **`retro25-main`**,
der Main bei jedem Start ausführt. Auf dem HDMI-Monitor erscheint das Menü;
**F12** öffnet die Core-Auswahl.

### 12. Spiele, ROMs und Platten

| Core | Wohin | Was |
|---|---|---|
| C64 | `/media/fat/games/C64/` | `.d64`, `.prg`, `.crt`, `.tap` (ROMs stecken schon im Core) |
| z486 | `/media/fat/games/Z486/` | `boot0.rom`, `boot1.rom` (**Pflicht**, aus `roms\z486\`), `freedos.vhd`, eigene `.vhd`/`.img`/`.iso` |

```
> scp roms\z486\boot0.rom roms\z486\boot1.rom roms\z486\freedos.vhd terasic@<board-ip>:/media/fat/games/Z486/
```

USB-Stick: Main findet Spiele auch unter `<Stick>/games/C64` bzw.
`<Stick>/games/Z486` (dann gehören auch `boot0.rom`/`boot1.rom` auf den
Stick). Bedienung, Festplatten, Windows 95, Sound: siehe die Core-READMEs.

**Geschafft.** Menü-Core per F12 → C64 bzw. Z486; im z486 öffnet
**Win + F12** das OSD (F12 allein braucht DOS selbst).

---

## Fehlersuche — Tipps und Tricks

### Erste Hilfe

| Symptom | Ursache / Abhilfe |
|---|---|
| HDMI bleibt schwarz nach dem Einschalten | Läuft Main? `systemctl status retro25-main`. Meldung „FPGA is uninitialized" = kein Retro25-Core im FPGA (Bootskript? Flash?). Konsole: erscheint `Retro25: lade retro25/core.rbf`? |
| HDMI schwarz nach einem harten Reset | `/media/fat` wurde nicht rechtzeitig eingehängt (Dateisystemprüfung). Warten oder `journalctl -b \| grep media-fat` ansehen |
| Linux bootet nicht mehr nach Schritt 10 | SD-Karte in den PC, auf der FAT-Partition `boot.scr.uimg.orig` nach `boot.scr.uimg` kopieren |
| Flash kaputt/falsch | lässt sich immer neu schreiben (SW5 AS-Modus, `flash.bat`); notfalls Terasics `golden_top_hps.jic` (liegt beim SD-Abbild) |
| Core lädt nicht, OSD zeigt „DDR busy" | Der alte Core gab den DDR nicht frei; er bleibt geladen. Erneut versuchen, sonst Neustart |
| z486 bleibt schwarz | `boot0.rom`/`boot1.rom` fehlen in `games/Z486` — auch auf einem Stick mit `games/Z486`, Main nimmt dann den Stick |
| Tastatur geht, Gamepad nicht | Gamepad zuerst im **Menü-Core** definieren (F12 → System → Define joystick buttons), dann im Core |
| WLAN weg nach Core-Wechsel | bekannt (USB-WLAN-Stick, Treiber). Netzwerkkabel nutzen |
| Windows 95 prüft beim Start die Platte | Vor jedem Core-Wechsel oder Reset Windows herunterfahren |
| Neuer Core nach `install.sh` noch der alte | Ein Neustart von Main lädt das FPGA nicht neu → `echo 'load_core /media/fat/_Retro25/Z486.rbf' > /dev/MiSTer_cmd` oder übers Menü |

### Main beobachten und fernsteuern

```
$ systemctl status retro25-main
$ journalctl -u retro25-main -f                  # Ausgabe live mitlesen
$ sudo systemctl stop retro25-main               # Main von Hand starten:
$ sudo /media/fat/MiSTer /media/fat/_Retro25/C64.rbf
```

Main liest Befehle aus der FIFO `/dev/MiSTer_cmd` (ohne `sudo`):

```
$ echo "load_core /media/fat/_Retro25/C64.rbf" > /dev/MiSTer_cmd
$ echo screenshot > /dev/MiSTer_cmd               # PNG in /media/fat/screenshots/<Core>/
```

Screenshots sind ideal, um ein Bild vom Bildschirm per `scp` an den PC (oder
an einen Helfer) zu schicken.

### Wenn Linux hängt: Magic SysRq statt Reset-Knopf

Der Reset-Knopf ist ein Stromausfall für die SD-Karte. Besser über die
serielle Konsole: **BREAK** senden (PuTTY: Rechtsklick auf die Titelleiste →
Special Command → Break), dann innerhalb von 5 s eine Taste:

| Taste | Wirkung |
|---|---|
| `w`, `l` | blockierte Tasks bzw. Backtraces aller CPUs anzeigen (Diagnose) |
| `s` | alle Daten auf die Karte schreiben (sync) |
| `u` | Dateisysteme schreibgeschützt einhängen |
| `b` | sofort neu starten |

Also: BREAK+`s`, BREAK+`u`, BREAK+`b`. Erst wenn auch das nicht reagiert:
Reset-Knopf. Vor riskanten Tests vorsorglich `sync`.

### Schreibgeschütztes Root

```
$ sudo retro25-rw          # Root beschreibbar (für apt, Konfiguration …)
$ sudo retro25-ro          # wieder schreibgeschützt
$ sudo retro25-rw-offen    # wenn ro "busy" meldet: wer hält Dateien offen?
```

Logs liegen im RAM: Nach einem Neustart ist `journalctl` vom letzten Lauf
leer. Für Fehler, die zum Absturz führen, die Konsole mitschreiben
(PuTTY: Session → Logging).

### Video

- `MiSTer.ini` liegt in `/media/fat/`. Bewährt: `video_mode=8`
  (1920×1080) und für den z486 `vscale_mode=1`. Funktionieren: `video_mode`
  0, 1, 6, 8; es fehlen `vsync_adjust=2` und `direct_video`.
- `p3/linux/video_debug.py` (per `scp` aufs Board, dann
  `sudo python3 video_debug.py`) misst die Bildrate und den Pixeltakt im FPGA — z. B. 60 Bilder/s und
  74,25 MHz bei 720p60.

### Sicherung der SD-Karte

Ist alles eingerichtet, ein Abbild ziehen (PowerShell als Administrator):

```
> python tools\sd_rescue.py backup <Datenträgernummer> D:\retro25-sd.img
```

Die Datenträgernummer zeigt `Get-CimInstance Win32_DiskDrive`
(`PHYSICALDRIVE4` → 4). Zurückschreiben mit balenaEtcher/Rufus.
`sd_rescue.py` kann außerdem ein beschädigtes Root über eine Abbild-Datei mit
`e2fsck` in Docker reparieren (Ablauf im Kopf des Skripts).

### Beim eigenen Bauen

- Immer über `Q:\` bauen (siehe Schritt 2).
- Nach jedem Bau den **HPS IO hash** vergleichen — weicht er ab, startet der
  Core nicht (alle Cores müssen dasselbe HPS-System haben).
- Quartus Pro hat Fallen bei MiSTer-Code; nach jedem Bau im Bericht nach den
  Warnungen **16788** (implizites Netz verliert seine Zuweisung) und **16754**
  (Register mit Startwert) suchen. Die Tabelle der Fallen steht in
  [`sys/de25/README.md`](sys/de25/README.md).
- Nach Änderungen am Fremdcode in `pro/`: Patches neu erzeugen und prüfen mit
  `python tools\apply_patches.py --check`.

---

## Verzeichnisse

```
sys/de25/       Port des MiSTer-Frameworks (sys_top_de25, hps_gp_bridge, sysmem …)
sys/vendor/     MiSTer-Original (setup.py, nicht im Repo)
sys/hps/        HPS-System aus Terasics GHRD (fetch_hps.py, nicht im Repo)
cores/<name>/   je Core: Rahmen, Patches (pro/*.patch), ip/, Testbenches
linux/main/     Main_MiSTer-Port: Patches, de25/, Docker-Bau, install.sh
linux/system/   Systemeinstellungen (ro-Root, fstab, USB, SysRq)
linux/boot/     U-Boot-Skript (HPS-first)
tools/          Python-/Batch-Skripte: setup, fetch, Bau, Flash, SD-Rettung
tb/             Testbenches eigener Module (Icarus/Questa)
p0/, p3/        Machbarkeitsversuche mit Diagnoseskripten
docs/           Roadmap, Analysen
roms/           eigene ROMs (nicht im Repo, nur README)
```

## Lizenz und Dank

Retro25: GPL-3.0-or-later. Die geholten Teile behalten ihre Lizenzen —
MiSTer-Framework, Main_MiSTer und MiSTer-Cores (GPL-2.0/3.0, siehe die
jeweiligen Repositories), z486 (Apache-2.0 für die CPU-Quellen, Microcode
ausgenommen, siehe [`cores/z486/README.md`](cores/z486/README.md)).

Dank an Sorgelig und die MiSTer-Entwickler, nand2mario (z486, ao486-Anteile)
und Terasic für das Board-Material.
