# roms/

Original ROMs (C64: BASIC, KERNAL, character set; 1541 DOS) are
copyrighted and are **not** checked in (`.gitignore`
only lets this README through). Place your own ROM files here locally.

Expected for the C64 core (P4), names as in VICE or `C64-DE25/roms`:

| File | Size | Contents |
|---|---|---|
| `basic-901226-01.bin` | 8 KB | BASIC V2 |
| `kernal-901227-03.bin` | 8 KB | KERNAL (rev. 3) |
| `chargen-901225-01.bin` | 4 KB | character set |
| `dos1541-325302-01+901229-05.bin` | 16 KB | 1541 DOS (as in MiSTer, receives its patch) |

`python tools/make_c64_roms.py` generates the C64 core's `.mif` files from
these locally (into `cores/c64/quartus/rtl/`, ignored by git). The
`.rbf` built with them contains the ROMs — for personal use only.

## z486 (P5)

`python tools/fetch_z486.py --roms` fetches the boot ROMs from the fixed
upstream commit into `roms/z486/`:

| File | Size | Contents |
|---|---|---|
| `boot0.rom` | 64 KB | Bochs BIOS (LGPL) |
| `boot1.rom` | 32 KB | Tseng ET4000 VGA BIOS (proprietary) |
| `freedos.vhd` | 32 MB | FreeDOS 1.3 test disk (upstream `freedos.zip`) |
| `games.vhd` | 256 MB | data disk (IDE 0-1), `tools/make_dos_disk.py` — e.g. with Doom shareware |
| `test.img`, `test.iso` | 1.44 MB / <1 MB | test floppy (floppy A:) and test CD (IDE 1-0), `make_dos_disk.py --type floppy/iso` |

They belong on the board in `/media/fat/games/Z486/`; Main loads them every
time the core starts (they are not in the `.rbf`).
