# roms/

Original-ROMs (C64: BASIC, KERNAL, Zeichensatz; 1541-DOS) sind
urheberrechtlich geschützt und werden **nicht** eingecheckt (`.gitignore`
lässt nur diese README durch). Eigene ROM-Dateien hier lokal ablegen.

Erwartet für den C64-Core (P4), Namen wie in VICE bzw. `C64-DE25/roms`:

| Datei | Größe | Inhalt |
|---|---|---|
| `basic-901226-01.bin` | 8 KB | BASIC V2 |
| `kernal-901227-03.bin` | 8 KB | KERNAL (Rev. 3) |
| `chargen-901225-01.bin` | 4 KB | Zeichensatz |
| `dos1541-325302-01+901229-05.bin` | 16 KB | 1541-DOS (wie MiSTer, bekommt dessen Patch) |

`python tools/make_c64_roms.py` erzeugt daraus die `.mif`-Dateien des
C64-Cores lokal (nach `cores/c64/quartus/rtl/`, von git ignoriert). Die
damit gebaute `.rbf` enthält die ROMs — nur für den eigenen Gebrauch.

## z486 (P5)

`python tools/fetch_z486.py --roms` holt die Boot-ROMs aus dem festen
upstream-Commit nach `roms/z486/`:

| Datei | Größe | Inhalt |
|---|---|---|
| `boot0.rom` | 64 KB | Bochs-BIOS (LGPL) |
| `boot1.rom` | 32 KB | Tseng-ET4000-VGA-BIOS (proprietär) |
| `freedos.vhd` | 32 MB | FreeDOS-1.3-Testplatte (upstream `freedos.zip`) |
| `games.vhd` | 256 MB | Datenplatte (IDE 0-1), `tools/make_dos_disk.py` — z. B. mit Doom-Shareware |
| `test.img`, `test.iso` | 1,44 MB / <1 MB | Testdiskette (Floppy A:) und Test-CD (IDE 1-0), `make_dos_disk.py --type floppy/iso` |

Sie gehören aufs Board nach `/media/fat/games/Z486/`; Main lädt sie bei
jedem Start des Cores (nicht in der `.rbf`).
