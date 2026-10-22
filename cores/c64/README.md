# C64 — MiSTers C64_MiSTer auf dem DE25

MiSTers [C64-Core](https://github.com/MiSTer-devel/C64_MiSTer) (fester Commit
in `tools/fetch_c64.py`), angepasst an Quartus Pro und Agilex 5.

- `vendor/` — Original ohne ROMs, PLL und OPL3-Firmware-Quellen. **Nicht im
  Repository**; `python tools/setup.py` (bzw. `tools/fetch_c64.py`) holt es.
- `pro/` — angepasste Kopien. Im Repository liegen nur die Diffs
  (`*.patch`, Pfade wie in `vendor/`); `tools/apply_patches.py` erzeugt daraus
  die Dateien.
- `rtl/` — eigene Module mit Testbench in `tb/`: `iecdrv_bitmem.v`
  (Spurpuffer des 1541), `opl3_mem.v` (Speicher der OPL3-Emulation)
- `ip/pll_c64` — feste PLL, `c64_de25.sdc` — Timing
- `test/make_test_media.py` — Testprogramm, Testdiskette und MGL (siehe unten)

## Bauen

```
python tools/setup.py                # einmalig: Fremdcode holen, pro/ erzeugen
python tools/make_c64_roms.py        # ROMs aus roms/ -> cores/c64/quartus/rtl/ (nicht im Repo)
python tools/make_core_qsf.py c64
Q:\tools\build_core.bat c64          # ~15 min; Ergebnis quartus/output_files/c64.core.rbf
```

Aufs Board: `c64.core.rbf` als `/media/fat/_Retro25/C64.rbf`. Die `.rbf`
enthält die ROMs aus `roms/` — nur für den eigenen Gebrauch, nicht weitergeben.
Belegung (Stand 2026-10-22): 35 589 ALMs (76 %), 222 M20K, Timing erfüllt.

## Takt (nur PAL, Entscheidung P4)

Feste PLL: VCO 2837,5 MHz (50 · 227 / 4), clk64 = 63,0556 MHz (5,6 ppm neben
MiSTer), clk_sys = clk64/2, clk48 (OPL) = 48,09 MHz, dazu clk64 mit +90° für
`SDRAM_CLK` über `sys/de25/ip/sdram_clk_ddio` (MiSTers invertierter Takt passt
nicht zum 1,8-V-SDRAM, siehe `cores/memtest/README.md`). Zur Laufzeit wird
keine PLL umgestellt: Die OSD-Option NTSC schaltet nur das VIC-Timing, der
Takt bleibt PAL (das Laufwerk liefe dann 3,8 % zu langsam).

## ROMs

`tools/make_c64_roms.py` erzeugt aus `roms/` (Namen in `roms/README.md`):
BASIC+KERNAL und Zeichensatz als `.mif`, das 1541-DOS (mit MiSTers 10-Byte-
Patch, identisch mit dessen Datei) als `.hex`. Für C64GS, japanisch,
DolphinDOS und 1581 gibt es keine ROMs: C64GS/japanisch lesen aus dem
Standard-ROM (spart 18 M20K), das 1581 hat ein leeres, per OSD ladbares ROM.

## Anpassungen (Überblick)

- Patches aus dem Vorgängerprojekt C64-DE25: SID, CIA (`mos6526.v`), Teile des
  1541-Laufwerks.
- Quartus-Pro-Fallen (Tabelle in `sys/de25/README.md`): Netze, die in
  `always` beschrieben werden, als `reg`/`logic`; Bezeichner vor ihrer
  Deklaration (implizite Netze verlieren ihre Zuweisung, Warnung 16788);
  Register mit Startwert im `always`-Block auf Modulebene (16754 — `static`
  hilft nicht); VHDL-`case` mit `others`; `entity` vor direkter Instanz.
- Speicher: Agilex 5 kann im Zwei-Port-Betrieb keine zwei Portbreiten und legt
  das Lesen beim gleichzeitigen Schreiben nicht fest — Spurpuffer und
  OPL3-Speicher neu (`rtl/`), sonst `ramstyle = "no_rw_check"`.
  `ram_init_file = " "` (Leerzeichen, „keine Datei") bringt Quartus Pro zum
  Absturz — die Laufwerks-ROMs lädt `$readmemh`.
- `sdram.v`: Datenregister ohne Clock-Enable (I/O-Register), kein `altddio_out`.

## Test am Board

```
python cores/c64/test/make_test_media.py          # schreibt nach cores/c64/test/out/
scp cores/c64/test/out/* terasic@<board>:/media/fat/games/C64/
echo "load_core /media/fat/games/C64/retro25test.mgl" > /dev/MiSTer_cmd
```

Die MGL lädt den Core, legt die Testdiskette ein und startet das Programm (es
startet nach dem Laden selbst). Im OSD liegen die Dateien unter „Mount #8"
bzw. „Load PRG". (Unter Git-Bash beim zweiten Argument von make_test_media.py
`MSYS_NO_PATHCONV=1` setzen, sonst wird der Pfad zu einem Windows-Pfad.)
Stand 2026-10-18:

| Test | Ergebnis |
|---|---|
| BASIC-Start, RAM-Test im SDRAM | ok |
| PRG laden und starten | ok |
| SID (Rauschgenerator, `$D41B`) | ok |
| Tastatur, OSD | ok |
| Diskette schreiben (Datei landet korrekt in der `.d64`) | ok |
| Diskette lesen (auch alle Sektoren der Spuren 16–19 einzeln) | ok |
| Spiel von USB-Stick (`/media/usb0/C64`), Ton über HDMI | ok |
| Joystick: Gamepad an Port 1, Ziffernblock an Port 2 (`joytest.mgl`), Nebulus mit Gamepad spielbar | ok |
| Modul (CRT Typ 0) 8 KB und 16 KB: Startcode läuft, ROM ab `$8100` mustergleich (`crttest8k/16k.mgl`) | ok |
| Modul mit Bankumschaltung (Magic Desk, Typ 19, 8 × 8 KB über `$DE00`, `crttestmd.mgl`) | ok |
| Kassette (TAP v1, selbst kodiert, 6 KB inkl. 4 KB Muster, `tapetest.mgl`): KERNAL-LOAD ST=0, keine Lesefehler, Daten ok | ok |

Das Laufwerk lädt Spuren in Bursts ab nicht ausgerichteten Adressen. Bursts
über eine 4-KB-Grenze verstoßen gegen AXI und kamen über F2SDRAM verfälscht an
(Lesefehler 22/23 genau an diesen Sektoren) — behoben in `sys` durch
`avl_burst_4k` (siehe `sys/de25/README.md`).
Die Testmodule bringen eigenen Startcode mit (Kennung `CBM80`) und prüfen
jedes ROM-Byte gegen das Muster `Adresse low XOR Adresse high`; grüner Rand =
OK, roter Rand = Fehler. Der 16-KB-Test prüft zugleich, dass EXROM/GAME aus
dem CRT-Kopf übernommen werden (sonst läge bei `$A000` BASIC). CRT-Daten
liegen im SDRAM ab `0x200000`, nicht im DDRAM.
Der Magic-Desk-Test kopiert seine Prüfroutine nach `$C000`, weil er beim
Umschalten sonst seinen eigenen Code ausblenden würde. Achtung: MiSTers
`cartridge.v` legt die Blöcke in Ladereihenfolge ab und adressiert sie direkt
über die Blocknummer (die Tabelle `lobanks` nutzt nur EasyFlash) — CHIP-Pakete
müssen aufsteigend in der Datei stehen (bei echten Modulen üblich).
Der Bandtest kodiert ein Programm selbst im CBM-Format (wie die
KERNAL-Schreibroutine: Dipole kurz/mittel, Bytemarker lang+mittel, ungerade
Parität, zwei Kopien mit Countdown `$89…`/`$09…`, XOR-Prüfsumme). Der Lader
`tapeload.prg` lädt per KERNAL-LOAD mit Meldungen und zeigt ST, die
Fehlerzähler beider Durchgänge, Endadresse und XOR-Summe. TAP-Daten liegen im
SDRAM ab `0x400000`. Zwei Eigenheiten von MiSTers `tape_subsystem.sv`:

- Ein Reset (auch durch Laden einer PRG mit „Reset & Run") wirft das Band
  aus → in der MGL zuerst die PRG, dann das Band; „Tape Auto Play" drückt
  danach PLAY.
- „Tape Auto Unload" wirft das Band schon beim letzten Zählschritt (~3 s vor
  dem Ende) aus, auch während es läuft. Endet die Datei direkt nach dem
  letzten Block, fehlt das Ende der zweiten Kopie (KERNAL: ST=$20,
  Prüfsummenfehler) → die Testdatei hat 10 s Nachlauf.

### Laufwerksanzeige

Unten rechts erscheint bei Laufwerkszugriffen z. B. „#8 12“ (Laufwerk 8,
Spur 12; gelb = aktiv). Das ist MiSTers OSD-Option **Drives OSD**
(Activity Only = Vorgabe, If Mounted, Debug, Off) — kein Fehler.

### Joysticks einrichten

Main kennt ohne Belegungsdatei weder das Gamepad noch den Ziffernblock als
Joystick — wie bei MiSTer muss jedes Gerät einmal definiert werden:

1. **Gamepad im Menü-Core:** F12 → System → „Define joystick buttons“, zuerst
   eine Richtung am Pad drücken. Erzeugt `config/inputs/input_<vid>_<pid>_v3.map`.
   Ohne diese System-Belegung bekommt das Pad keine Spielernummer: Main
   ordnet ein Gerät erst einem Spieler zu, wenn ein Knopf in dieser Belegung
   vorkommt, und die Ersatzbelegung nimmt Xbox-Codes (`0x130` …), die z. B.
   das Manta-Pad (`081f:e401`, Codes `0x120`–`0x129`) nie sendet.
2. **Im C64-Core:** F12 → „Define C64 buttons“, für das Pad und für die
   Tastatur (Ziffernblock 8/2/4/6, Feuer z. B. Ziffernblock 0; Rest mit Enter
   beenden). Erzeugt `config/inputs/C64_input_<vid>_<pid>_v3.map`.
3. **Ziffernblock als Joystick:** Num Lock schaltet reihum Maus → Joystick 1
   → Joystick 2 → Normal (Meldung „Kbd mode: …“). Die Einstellung gilt bis
   zum nächsten Core-Laden.

Das erste Gamepad wird Spieler 1 = Port 1; Ports tauschen im OSD mit
„Swap Joysticks“. Im Testprogramm zeigt Port 1 auch Tasten der
Tastaturmatrix-Spalte 7 (1, 2, CTRL, SPACE …) — das ist kein Joystick.
