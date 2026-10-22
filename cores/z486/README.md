# z486 — 486-PC (P5)

nand2marios [z486_MiSTer](https://github.com/nand2mario/z486_MiSTer) — ein
486-PC (etwa 486DX2-66) — im Retro25-Rahmen.

**Lizenz:** z486_MiSTer hat keine Lizenzdatei; die CPU (`src/z486`) steht nur
für `*.sv`, `*.svh`, `*.py`, `*.md` unter Apache-2.0, der Microcode
(`ucode.hex`) ist ausdrücklich ausgenommen. Deshalb liegt **nichts** davon im
Repository — auch nicht die angepassten Kopien (`pro/`). `tools/fetch_z486.py`
holt den Fremdcode aus einem festen Commit nach `vendor/`, `make_pro.py`
erzeugt `pro/` per Textersetzung (die Suchmuster darin sind kurze
Ausschnitte). Gebaute Bitstreams enthalten den Microcode: **nicht
weitergeben**, nur selbst bauen.

## Stand (2026-10-22)

| Bereich | Stand |
|---|---|
| CPU, BIOS, VGA (ET4000, 2 MB) | ✔ FreeDOS, Windows 95 OSR2 |
| Festplatte (IDE, `.vhd`), Diskette, CD-ROM (ISO) | ✔ lesen und schreiben |
| Tastatur, Maus, Joystick | ✔ |
| Sound Blaster, OPL3 | ✔ (Doom 37 fps, Quake mit Sound) |
| SVGA-Framebuffer | ✔ bis 1024×768×8, 800×600×16, 640×480×24 |
| x87-FPU | ✔ Quake `timedemo demo1` 8,3 fps |
| Gemeinsamer Ordner (MISTERFS) | ✔ unter DOS |
| Screenshot (Main) | ✔ auch im SVGA-Modus |
| Bekannt | gelegentlich 20–30 s Pause beim Windows-Start-Jingle |

Belegung: 43 159 ALMs (92 %), 282 M20K, Timing bei 85 MHz erfüllt,
HPS IO hash gleich.

## Bauen

```
python tools/setup.py                    # einmalig: holt Fremdcode, ROMs, erzeugt pro/
python cores/z486/make_pro.py            # nach Änderungen an make_pro.py: pro/, core.tcl, probe/
python tools/make_core_qsf.py z486
Q:\tools\build_core.bat z486             # ~20 min; Ergebnis quartus/output_files/z486.core.rbf
```

Aufs Board: `z486.core.rbf` als `/media/fat/_Retro25/Z486.rbf`; `boot0.rom`
und `boot1.rom` (aus `roms/z486/`, `tools/fetch_z486.py --roms`) nach
`/media/fat/games/Z486/` (bzw. auf den Stick, siehe „USB-Stick“) — Main lädt
sie bei jedem Start des Cores über den DDR in den Core. Einen neuen Core lädt
ein Neustart von Main **nicht**: `echo 'load_core /media/fat/_Retro25/Z486.rbf'
> /dev/MiSTer_cmd` oder über das Menü. Vorher Windows herunterfahren (ein
DOS-Prompt ohne laufendes Programm ist unkritisch), sonst prüft Windows beim
nächsten Start die Platte.

## Bedienung (Z5, 2026-10-18)

- **OSD: Win + F12** oder die Menü-Taste — F12 allein geht bei PC-Cores
  nicht (Main `is_f12_mod_needed()`: DOS-/Windows-Programme brauchen F12).
- Festplatte: OSD → **IDE 0-0** → `.vhd` (Rohabbild) → **Reset and apply
  HDD**. Gemerkt wird sie erst mit **Save settings** (`config/Z486sys.cfg`),
  danach bindet Main sie bei jedem Start ein.
- Eine MGL hilft beim x86 nicht: Sie bindet die Platte erst nach dem
  Core-Start ein, wenn das BIOS die IDE schon abgefragt hat, und speichert
  nichts.
- Testplatte: `tools/fetch_z486.py --roms` → `roms/z486/freedos.vhd`
  (upstream `verilator/freedos.zip`, FreeDOS 1.3, 32 MB FAT16) nach
  `/media/fat/games/Z486/`. Bootet bis `C:\>` (Tastatur geht).

## Spiele (Z6, 2026-10-18)

Datenplatte an IDE 0-1 (unter FreeDOS `D:`), erzeugt mit
`tools/make_dos_disk.py` (Docker: mkfs.fat + mtools), z. B.
`python tools/make_dos_disk.py roms/z486/games.vhd --size 256 <ordner>=DOOMINST`.

Doom 1.9 Shareware (`doom19s.zip` von idgames, Installer unter DOS
ausgeführt): läuft flüssig, Sound Blaster (220/IRQ 5/DMA 1) mit Musik und
Effekten über HDMI. `doom -timedemo demo3`: 2134 Gametics in 2018 Realtics
= **37,0 fps** (Standardeinstellungen der Shareware; upstream nennt 29,1 fps
bei voller Detailstufe auf dem DE10-Nano).

## Maus und Joystick (2026-10-19)

- **Maus** (USB, über Main als PS/2-Maus): geht mit Main-Patch 0007 — der
  Terasic-Kernel hat kein `mousedev`, vorher kamen nur die Tasten an.
  FreeDOS lädt `CTMOUSE` in `FDAUTO.BAT`; Test `C:\FREEDOS\BIN\CTMOUSE\MOUSETST`.
  Doom: `use_mouse 1` in `DEFAULT.CFG` (SETUP: Keyboard + Mouse) — die
  Shareware-Vorgabe war 0.
- **Joystick** (Game-Port 201h, USB-Pads über Main): Main schickt die
  Tasten erst, wenn das Pad **im z486** belegt ist — OSD (Win + F12) →
  Systemseite → **Define joystick buttons** (eine Datei
  `config/inputs/Z486_input_<vid>_<pid>_v3.map` gilt für alle gleichen Pads;
  vorher Main-Belegung im Menü-Core, siehe `cores/c64/README.md`). Prüfen
  ohne Spiel: `debug`, `i 201` → `F0` ohne, `E0` mit Button 1 (Tasten aktiv
  low, Bits 4–7). Doom: SETUP → Keyboard + Joystick, kalibrieren — läuft.
  Doom kennt neben der Tastatur nur Maus *oder* Joystick.

## Diskette und CD-ROM (Z7, 2026-10-19)

Testabbilder: `tools/make_dos_disk.py … --type floppy` (1,44 MB FAT12) bzw.
`--type iso` (ISO 9660 + Joliet), je mit `TEST\DATA.BIN` (512 KB).

- **CD-ROM** (OSD **IDE 1-0**, `.iso`): geht. FreeDOS lädt UDVD2 („No V2.0C+
  PCI!“, findet `IDE0 Secondary-master` über die ISA-Ports) + SHSUCDX → `E:`.
  `fc /b A:\TEST\DATA.BIN E:\TEST\DATA.BIN`: keine Unterschiede.
- **Diskette lesen** (OSD **Floppy A:**): geht.
- **Diskette schreiben** (2026-10-20): geht nach Korrektur von upstream
  [#125](https://github.com/nand2mario/z486_MiSTer/issues/125).
  Ursache: `sdram.v` gab Port 0 (CPU) feste Vorfahrt vor Port 1 (DMA).
  Beim Schreiben pollt das BIOS auf den Interrupt, die CPU belegt den
  Speicher dabei in ~83 % der Takte. Die DMA bekam für den Floppy-Controller
  kaum Bytes (gemessen ~150 B je 250 ms, Zähler im Core + Main-Debugpatch).
  Nach ~2 s bricht das BIOS ab, DOS hängt. Lesen (Gerät → Speicher) und
  Sound-DMA fiel das nicht auf; die Verilator-Simulation zeigte es nicht.
  Abhilfe (`make_pro.py`): DMA vor CPU wie im PC (HOLD/HLDA). Die DMA hat
  höchstens eine Anfrage offen und kann die CPU nicht aushungern.
  Test: `copy C:\FREEDOS\BIN\FC.EXE A:\Z.EXE` dauert 0,2 s für 28 Sektoren
  (vorher Hänger), die Datei auf `test.img` ist bytegleich.
- Mit eingelegter Diskette bootet das BIOS von A: (`Boot 1st:
  Floppy/Hard Disk`) → OSD **Hardware → Boot 1st: Hard Disk**.

## USB-Stick und Windows 95 (2026-10-20)

- **Images vom Stick:** Main sucht den Core-Ordner zuerst auf den Sticks
  (`/media/usbN/games/Z486`), dann auf der SD-Karte, und nimmt nur den
  ersten Treffer. Gibt es `games/Z486` auf dem Stick, zeigt das OSD nur
  dessen Dateien — und Main lädt auch **`boot0.rom`/`boot1.rom`** von dort.
  Fehlen sie, bleibt der Bildschirm schwarz (kein BIOS) → ROMs mit auf den
  Stick kopieren.
- Die Slots **IDE 0-x** nehmen nur `.vhd` (Rohabbild, eine `.img` einfach
  umbenennen), **IDE 1-x** (CD) `.vhd/.iso/.cue/.chd`, Floppy `.img/.ima/.vfd`.
  Ein Platten-Image an IDE 1-x lehnt Main ab („Cannot hot-mount HDD image
  to CD!“).
- **Windows 95 OSR2** (englisch, ISO an IDE 1-0, leere 512-MB-`.vhd` an
  IDE 0-0, Boot 1st: CD-ROM, nach dem ersten Neustart Hard Disk) installiert
  und startet bis zum Desktop; Dateisystem und Auslagerung laufen 32-bit
  (kein MS-DOS-Kompatibilitätsmodus). Ein japanisches Win95-Abbild blieb
  dagegen nach dem Laden von `DISPLAY.DRV` stehen (nicht weiter verfolgt).
- **Schreibtempo:** Main öffnete Images mit `O_SYNC` — jeder IDE-Schreibbefehl
  (unter Windows oft 1 Sektor) wartete auf den Datenträger, Stick wie
  SD-Karte schaffen so nur ~150 Vorgänge/s (~40 KB/s, die Installation
  dauerte Stunden). Main-Patch 0008 puffert in Linux und ruft `fsync` nach
  1 s ohne Schreiben: `xcopy` unter Win95 schreibt jetzt ~300–400 KB/s.
  Strom oder Stick erst ziehen, wenn ~1 s nichts mehr geschrieben wurde.
- US-Tastaturbelegung in Windows: `:` liegt auf Shift + Ö (sonst kommt `;`).

## Gemeinsamer Ordner (Z7, 2026-10-22)

Dateiaustausch mit dem PC ohne Plattenabbild: Der Ordner `games/Z486/shared`
(auf dem Stick bzw. der SD-Karte, je nachdem wo `games/Z486` liegt) erscheint
unter DOS als Netzlaufwerk.

- Treiber: `misterfs.exe` aus ao486_MiSTer (MIT-Lizenz;
  `tools/fetch_z486.py --roms` holt ihn nach `roms/z486/`). Aufruf mit dem
  Laufwerksbuchstaben **ohne** Schrägstrich: `MISTERFS E`. Am bequemsten nach
  `C:\` kopieren und in die `AUTOEXEC.BAT` eintragen. Mit EMM386 den Bereich
  ausnehmen: `X=CE00-CFFF`.
- Geprüft unter Win95-DOS (Command prompt only): `dir`, `type`, `copy` in
  beide Richtungen, `fc /b` bytegleich. Unter der Windows-Oberfläche noch
  nicht getestet.
- **Wie es funktioniert:** Der Treiber (ein DOS-Redirector, INT 2Fh) legt jede
  Dateianfrage in einen 8-KB-Briefkasten bei PC-Adresse `CE000`. Main
  (`x86_share.cpp`) pollt ihn im DDR bei `0x300CE000`, führt die Anfrage mit
  echten Dateien aus und legt die Antwort zurück. Beim ao486 liegt der ganze
  PC-Speicher im DDR; beim z486 liegt er im SDRAM. Deshalb leitet der Core
  `CE000–CFFFF` als **Geräteseite** (ungecacht, direkt) über denselben Weg ins
  DDR wie den linearen SVGA-Framebuffer (`main_memory`, Zustände
  `FB_WRITE`/`FB_READ`). Testbench `tb/tb_main_memory_share.v`.
- Main: Patch 0009 (Briefkasten ausgerichtet kopieren, sonst SIGBUS) und
  `shmem_map` für Adressen mitten in einer Seite (`linux/main/de25/shmem.cpp`).
- **Falle (sys):** Der z486 lässt `DDRAM_BE` beim Lesen auf dem Wert des
  letzten Schreibzugriffs stehen. Über F2SDRAM kamen dann nur diese Bytes
  zurück, der Rest war 0 — `sysmem_de25` liest jetzt immer mit `FF`
  (`sys/de25/README.md`). Teil-Schreibzugriffe funktionieren.
- Stresstest `SHTEST.COM` (50 000 zufällige Byte-/Wort-/Dword-Zugriffe auf
  `CE00:0100–1FFF` gegen eine Kopie im RAM): fehlerfrei.
- Das BIOS testet beim Start `CE0A0`/`CF0A0` als RAM und tastet `CF000–CFE00`
  nach Options-ROMs ab — jetzt im DDR, wie beim ao486; harmlos.

## SVGA (Z7, 2026-10-22)

Modi ab 256 Farben (ET4000-Modi, VESA) laufen über den **Framebuffer im
DDR**: Die CPU schreibt über `main_memory` (Zustände `FB_WRITE`/`FB_READ`,
banked Fenster `A0000` oder lineare Apertur bei 248 MB) nach `0x3F800000`,
der Scaler (ascal) liest von dort und nimmt die Palette des Cores
(`MISTER_FB=1`, `MISTER_FB_PALETTE=1` in `core.tcl`). Kostet ~160 ALMs.

- DOS: `SVGATEST.COM` (VESA `101h`, 640×480×256, 16×16 Farbfelder) korrekt.
- Windows 95: Treiber **Tseng Labs ET4000**, 640×480, 800×600 und 1024×768
  mit 256 Farben laufen (Grauverlauf weich).
- **Lesepuffer** (`make_pro.py`, `main_memory`): Jeder Lesezugriff auf den
  Framebuffer war ein einzelner Weg ins DDR (~42 Takte); Windows liest viel
  und war zäh. Das zuletzt gelesene 64-bit-Wort bleibt gepuffert, Schreiben
  der CPU wird nachgeführt (nur sie schreibt den Framebuffer), der Briefkasten
  ist ausgenommen. Gemessen mit `FBREAD.COM` (VESA 101h, 10 × 320 KB):

  | | ohne | mit Lesepuffer |
  |---|---|---|
  | Lesen byteweise | 1 420 KB/s | 3 640 KB/s |
  | Lesen dwordweise | 5 294 KB/s | 8 320 KB/s |
  | Schreiben dword | 14 560 KB/s | 14 560 KB/s |

  Den Rest kostet der ungecachte Gerätezugriff der CPU selbst (~23 Takte je
  Treffer); mehr Wörter vorauszulesen brächte wenig.
- **Windows 95 mit gemeinsamem Ordner:** `C:\WINDOWS\SYSTEM.INI`, Abschnitt
  `[386Enh]`: `EMMExclude=CE00-CFFF`. Sonst legt Windows im Briefkasten
  (der jetzt wie RAM aussieht) eigenen Code ab; Befehle aus einer
  Geräteseite liefert der z486 als `FF` → Windows hängt beim Start-Jingle.
  Beim ao486 gilt dieselbe Regel (dort überschriebe Windows den Briefkasten).
- Screenshot (Main) geht auch im Framebuffer-Modus (Main-Patch 0010,
  Palette über UIO `0x4E`, `sys/de25/README.md`).
- Lesbarkeit am Monitor: HDMI auf 1080p (`video_mode=8`), für scharfe
  Pixel `vscale_mode=1` (ganzzahlig; 1024×768 dann 1:1 in der Mitte).
- Farbtiefen mit dem ET4000-Treiber (2 MB Bildspeicher): 256 Farben bis
  1024×768, 16 bit bis 800×600, 24 bit bis 640×480 — größere Kombinationen
  bietet der Treiber nicht an (z. B. 1024×768×16 = 1,5 MB).
- Offen: gelegentlich 20–30 s Pause beim Start-Jingle von Windows
  (sporadisch).

## x87 (Z7, 2026-10-22)

FPU wie upstream an (`ENABLE_X87 = 1`): 43 159 ALMs (92 %), 282 M20K, Timing
bei 85 MHz erfüllt. Anpassungen (`make_pro.py`): die drei ROMs
(`x87_ucode_rom`, `x87_command_rom`, `x87_logexp_rom`) von M10K auf M20K,
Inhalt weiter aus den `.mif`; der Stapel `x87_stack_mem` (8 × 80 bit, zwei
Schreibports) über den herstellerneutralen Zweig als Register — Agilex 5
kennt BIDIR_DUAL_PORT mit OLD_DATA nicht.

`FPUTEST.COM` (Testdiskette): FPU erkannt; π, √2, sin(1), cos(1), ln(2),
1/3, atan(1) bitgenau; FMUL ~9 Mio/s, FDIV ~1,3 Mio/s (Größenordnung
486DX2-66).

**Quake 1.06 Shareware** (`quake106.zip`, MD5 `8cee4d03…1357`, im Container
mit `lhasa` entpackt, als `quake.vhd` an IDE 0-1): läuft unter Win95-DOS
(„Command prompt only“), `timedemo demo1` = **8,3 fps** (320×200; ein echter
486DX2-66 schafft ~8–10). Win95-DOS setzt kein `BLASTER` und lädt keinen
Maustreiber — Startdatei `Q.BAT`: `set BLASTER=A220 I5 D1 H5 P330 T6`,
`CTMOUSE` (aus FreeDOS), `QUAKE`.
Sound und Maus gehen damit. „MSCDEX not loaded, Music is disabled“ ist
normal: Quakes Musik sind CD-Audio-Spuren der Vollversion (Shareware ohne).

**FreeDOS-Testplatte:** `vinfo /m` (V8Power 2021) meldet einen 486 ohne
CPUID als **80186** (Fehler in vinfo, upstream 2025 behoben, Commit
`ccaff7ac`) — `FDAUTO.BAT` nimmt dann den 8086-Zweig: keine Maus, keine CD.
Abhilfe in `C:\FDAUTO.BAT` nach `if errorlevel 2 goto Support286`:
`if errorlevel 1 goto Support386`; deutsche Tastatur: `keyb gr` vor der
`vinfo`-Zeile. (Der z486 rechnet `SHR` mit CL=32 und `PUSH SP` richtig,
in `debug` geprüft.)

## Anpassungen (`make_pro.py`, Gründe dort)

| Datei | Änderung |
|---|---|
| `z486_mister.sv` | ohne x87; IOPLL `pll_z486` (`pll` heißt schon das PLL-Modul des HPS-Systems); `SDRAM_CLK` 90° über `sdram_clk_ddio` (Phasenfenster `cores/sdram486test`); LFB-Eingänge wie `sys/emu_ports.vh`; **ohne `assign gamma_bus = 'z;`** |
| `src/memory/sdram.v` | Quartus Pro: Deklaration vor Verwendung, DQ-Ausgangsregister ohne Enable (I/O-Register) |
| `src/z486/*` | Microcode-ROM inferiert (altsyncram mit clock1 auf Agilex verboten), `ramstyle` M20K, Nettyp-Direktive |
| `src/common/dpram.v` | `no_rw_check`, Port B synchron (sonst Logik bzw. doppeltes RAM) |
| `src/soc/sound/sound.v`, `hps_ext.v`, `cdda.v`, `saa1099.sv` | Quartus-Pro-Fallen 16788/16754, Nettyp-Direktive |
| `src/z486/x87/*_rom.sv`, `x87_stack_mem.sv` | M10K → M20K; Stapel als Register (BIDIR + OLD_DATA auf Agilex 5 verboten) |
| `src/z486/z486_pkg.sv`, `l1_cache.sv`, `src/memory/main_memory.sv` | Briefkasten `CE000–CFFFF` als Geräteseite ins DDR (gemeinsamer Ordner, siehe unten); in `main_memory` Deklarationen vor die erste Verwendung (Questa) |

Die Dateien, die `z486_platform.svh` einbinden, liegen unverändert in `pro/`,
damit `include` die angepasste Fassung findet (es sucht zuerst im Ordner der
einbindenden Datei) — so braucht das Projekt kein `VERILOG_CU_MODE MFCU`,
das auch auf alle sys-Dateien wirken würde.

## Fallen

- **Tri-State-Treiber auf internen Bussen:** `assign gamma_bus = 'z;` neben
  den echten Treibern (`hps_io`, `gamma_corr`) ließ Quartus Pro den Bus
  falsch auflösen (Warnungen 13034/13035/13028) — CPU und BIOS liefen, das
  Bild blieb schwarz. Nach jedem Bau auf 1303x prüfen.
- **Main stürzte mit SIGBUS ab** (`x86_init`): `memset` und Dateiladen direkt
  in die `/dev/mem`-Abbildung des DDR-Fensters (Device-Speicher) — wie beim
  C64 (Patch 0005); Main-Patch 0006.
- Diagnose ohne UART: LED0 PLL, LED2 erster Befehl der CPU, LED4 BIOS aus dem
  DDR kopiert, LED6 sys-PLL. Der Debug-UART des z486 (BIOS-Meldungen) führt
  bei uns nirgends hin.
