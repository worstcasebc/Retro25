# linux/main — Main_MiSTer auf dem DE25-Nano

Main_MiSTer ist MiSTers Linux-Programm: Es zeichnet das Menü (OSD), liest
Tastatur und Gamepads, lädt Cores und spielt Disk-Images ein. Das Original
(`linux/vendor/main_mister`, unverändert, `tools/fetch_main.py`) ist für den
32-bit-ARM des DE10-Nano geschrieben. Hier liegt, was es für das DE25-Nano
(aarch64, Agilex 5) braucht.

## Aufbau

| Pfad | Zweck |
|---|---|
| `build.sh` | Quellbaum anlegen (vendor + Patches + de25/) und bauen |
| `docker/Dockerfile` | Bauumgebung: Ubuntu 22.04 arm64 wie auf dem Board (für `tools/build_main.py`) |
| `Makefile` | wie das Original, aber nativer gcc und Ubuntu-Bibliotheken |
| `de25/fpga_io.cpp` | **neu:** gp_out/gp_in über `hps_gp_bridge`, Core laden per Overlay, WLAN-Hook |
| `de25/shmem.cpp` | **neu:** nur bekannte Adressen abbilden (Parameterseite als Datei, DDR-Fenster); `shmem_put`/`shmem_get` kopieren ausgerichtet (das Fenster ist per `/dev/mem` nur als Device-Speicher abbildbar: `memset`/`memcpy` lösen dort SIGBUS aus); Adressen mitten in einer Seite gehen (ab Seitenanfang abbilden, `mmap` verlangt Seitengrenzen — sonst EINVAL bei x86_share `0x300CE004`) |
| `de25/smbus.cpp` | **neu:** I2C zum HDMI-Sender über den I2C-Master im FPGA statt `/dev/i2c-N` |
| `patches/0001-…` | Amiga-Plattenstrukturen mit 32-bit-Feldern (betrifft auch IDE/z486) |
| `patches/0002-…` | Main auf CPU 3, Hilfsthread auf CPU 2 (die Cortex-A76) |
| `patches/0003-…` | drei Stellen, die nur auf 32 bit richtig übersetzen |
| `patches/0004-…` | HDMI-PLL-Rechnung ganzzahlig (N/M/C) für die Agilex-5-IOPLL |
| `patches/0005-…` | C64: Diskettenabbild (G64) erst im RAM bauen, dann per `shmem_put` in den DDR (sonst SIGBUS beim Einlegen einer D64) |
| `patches/0006-…` | x86 (z486/ao486): BIOS-ROMs und Speicherfüllung per `shmem_put` in den DDR statt `memset`/Dateiladen in die Abbildung (sonst SIGBUS in `x86_init`) |
| `patches/0007-…` | Mausbewegung direkt aus evdev, wenn `/dev/input/mouseN` fehlt (Terasic-Kernel ohne `CONFIG_INPUT_MOUSEDEV`; vorher kamen nur die Tasten an) |
| `patches/0008-…` | Platten-/Disketten-Images (`ide_img_mount`) ohne `O_SYNC`; `fsync` nach 1 s ohne Schreiben und vor Image-Wechsel. Mit `O_SYNC` schafften Stick und SD-Karte nur ~150 Schreibvorgänge/s (Win95 ~40 KB/s, jetzt ~8–10× schneller) |
| `patches/0010-…` | Screenshot im Framebuffer-Modus eines Cores (`MISTER_FB`): Bild direkt aus dem DDR (Basis/Zeilenlänge aus `UIO_GET_FB_PAR`), bei 8 bpp Palette über den neuen UIO-Befehl `0x4E` (Schattenkopie in `sys_top_de25`); vorher nur Streifen aus dem VGA-Eingang des Scalers |
| `patches/0009-…` | Gemeinsamer Ordner (x86_share): MISTERFS-Rahmen per `shmem_get` in normalen Speicher holen, dort bearbeiten, Antwort per `shmem_put` zurück (direkt im DDR-Fenster → SIGBUS, wie 0005/0006) |
| `board/retro25-main.dts` | Overlay, mit dem Main einen Core lädt |
| `board/retro25-switch-hook` | schaltet WLAN beim Core-Wechsel aus und wieder ein (P0) |
| `board/retro25-main.service` | systemd-Dienst: startet Main beim Booten, nach Absturz neu |
| `install.sh` | richtet alles auf dem Board ein (`/media/fat`, Overlay, Hook, Module) |

Analogie: Der Fremdcode ist ein gekauftes Möbelstück. Wir sägen nicht daran,
sondern legen eine Liste mit Änderungen daneben (Patches) und tauschen zwei
Teile komplett aus (de25/). Kommt eine neue Version, prüft man nur die Liste.

## Bauen

**Auf dem PC (empfohlen):** in einem arm64-Container mit demselben Ubuntu
wie auf dem Board. Docker Desktop führt ihn per QEMU aus; das Ergebnis läuft
unverändert auf dem Board.

```
python tools/build_main.py                                # -> linux/main/build/MiSTer
python tools/build_main.py --deploy terasic@192.168.178.125   # + nach ~/retro25/ kopieren
```

Das Skript baut beim ersten Mal das Image `retro25-arm64` aus
`docker/Dockerfile`, kopiert die Quellen ins Docker-Volume `retro25-build`
und ruft dort `build.sh` auf. Warum ein Volume? Direkt aus dem
Windows-Ordner ist jeder Dateizugriff im QEMU-Container sehr langsam; im
Volume bleiben außerdem die Objektdateien liegen, ein zweiter Bau übersetzt
nur Geändertes. Optionen: `--clean` (alles neu), `--rebuild-image`,
weitere make-Argumente nach `--` (z. B. `-- DEBUG=1`). Änderungen am
Makefile lösen kein Neuübersetzen aus → `--clean`.

**Auf dem Board:**

```
sudo apt install build-essential libimlib2-dev libfreetype-dev libpng-dev                  libbz2-dev zlib1g-dev libbluetooth-dev
cd linux/main && ./build.sh          # -> build/src/bin/MiSTer
```

Zur Laufzeit braucht das Board nur `libimlib2` (die übrigen Bibliotheken hat
Ubuntu schon).

## Einrichten und starten

```
cd ~/retro25 && sudo ./install.sh testpattern.core.rbf   # nach --deploy; Core-Datei dazulegen
```

`install.sh` richtet Main als Dienst `retro25-main` ein und startet ihn —
wie beim MiSTer läuft Main danach immer, auch nach jedem Neustart. Main ist
der Dolmetscher zwischen USB-Tastatur und Core: Ohne Main gibt es weder
F12 noch Tasten im Core.

```
systemctl status retro25-main          # läuft Main?
journalctl -u retro25-main -f          # Ausgabe mitlesen
sudo systemctl stop retro25-main       # vor einem Start von Hand
sudo /media/fat/MiSTer /media/fat/_Retro25/Testpattern.rbf
```

Den Start-Core lädt U-Boot (`retro25/core.rbf` auf der Boot-Partition);
seinen Pfad bekommt Main aus `RETRO25_CORE` in `/etc/default/retro25`
(beim ersten `install.sh` der erste angegebene Core). Beides muss
zusammenpassen.

Main startet nur, wenn ein Retro25-Core (mit `hps_gp_bridge`) im FPGA
läuft — sonst meldet es „FPGA is uninitialized“ und beendet sich; der
Dienst versucht es alle 3 s erneut.

**Fernsteuerung:** Main liest Befehle aus der FIFO `/dev/MiSTer_cmd`. Der
Dienst läuft mit `UMask=0000`, damit sie nach jedem Start (auch nach jedem
Core-Wechsel, Main legt sie dann neu an) für alle beschreibbar bleibt —
so geht es ohne `sudo`, z. B. für Tests per `ssh`:

```
echo "load_core /media/fat/_Retro25/Memtest.rbf" > /dev/MiSTer_cmd
echo screenshot > /dev/MiSTer_cmd      # PNG unter /media/fat/screenshots/<CORE>/
```

`/media/fat/_Retro25` und `/media/fat/games` (Spiele je Core, z. B.
`games/C64`) gehören dem Nutzer `terasic` (ohne `sudo` hineinkopieren);
`install.sh` legt sie an. Cores, die `install.sh` schreibt, gehören root.

## Was anders ist als beim DE10-Nano (Stand P3)

- **Core laden** dauert ~2 s (Kernel-FPGA-Manager über das SDM) statt
  Main selbst über den FPGA-Manager des Cyclone V.
- **DDR-Sperre vor dem Laden:** Main hält alle drei DDR-Ports im FPGA an
  und wartet, bis sie leer sind (`f2s_halt()` in `de25/fpga_io.cpp`,
  Register `0x2001_7000`, `sys/de25/f2s_halt_de25.v`). Ein Umladen mitten in
  einem F2SDRAM-Zugriff ließe die SMMU und damit Linux hängen. Werden die
  Ports nicht leer, bleibt der alte Core („DDR busy“ im OSD). Ein Core ohne
  das Register (älterer Stand) wird mit Warnung trotzdem geladen.
- **Menü-Core:** wie bei MiSTer `/media/fat/menu.rbf`, die übrigen Cores in
  `/media/fat/_Retro25/` (`sudo ./install.sh menu.core.rbf X.core.rbf`).
  Als Start-Core lädt ihn U-Boot (`boot/retro25-bootscr.sh install
  menu.core.rbf`); `/etc/default/retro25` enthält dann `RETRO25_CORE=`
  (leer, Main erkennt das Menü selbst).
- **HDMI-Sender:** Er hängt an FPGA-Pins, nicht am I2C des HPS. Main
  erreicht ihn über den I2C-Master im FPGA (`0x2001_6000`): `de25/smbus.cpp`
  ersetzt `smbus.cpp` mit derselben Schnittstelle, es gibt genau einen Bus.
  Beim ersten `i2c_open` übernimmt Main den Bus; bis dahin stellt
  `hdmi_config` im FPGA den Sender auf ein Bild ein.
- **DDR-Fenster** (Scaler, Framebuffer, Core-Speicher, Speicherstände):
  MiSTer-Adressen `0x2000_0000–0x3FFF_FFFF` liegen physisch bei
  `0xA000_0000–0xBFFF_FFFF` (seit P3, reserviert per U-Boot);
  `de25/shmem.cpp` rechnet um. Andere Adressen liefert `shmem_map()` nicht.
- **Videomodus:** `video_mode` wirkt (seit P3 Schritt 4). Die HDMI-PLL des
  Agilex 5 teilt nur ganzzahlig; Patch `0004-hdmi-pll-ganzzahlig.patch`
  rechnet N/M/C statt M/K (Abweichung meist 0 ppm, 640×480: +17 ppm). Es
  fehlt `vsync_adjust=2` (Low-Latency-Nachregelung der PLL, fraktional) und
  `direct_video`. `install.sh` setzt `video_mode=0`, falls keiner gesetzt ist.
- **Core-Datei im RAM:** Main schreibt den zu ladenden Core nach
  `/run/retro25-fw/retro25/main.core.rbf` und setzt den Firmware-Suchpfad
  des Kernels auf `/run/retro25-fw` (das Root ist seit P3a schreibgeschützt,
  `linux/system/`). Das Overlay `main.dtbo` bleibt in `/lib/firmware`.
- **Neustart** über `/sbin/reboot`; U-Boot lädt danach den Start-Core.
- **Nach einem Core-Wechsel** ersetzt Main sich per `execl` selbst, statt
  wie das Original per doppeltem `fork` einen losgelösten Nachfolger zu
  starten — sonst verlöre systemd den Prozess aus dem Blick.
- **Ohne Wirkung:** `fpga_core_read/write` (nutzt kein Teil von Main),
  Laden mit Konfiguration (`cfg`, U-Boot-Umgebung im DDR).
- Kernel ohne `uinput`, `hidraw`, `joydev`: Main meldet „Unable to open
  /dev/uinput“; Tastatur und Gamepads gehen trotzdem (evdev).
