# C64 — MiSTer's C64_MiSTer on the DE25

MiSTer's [C64 core](https://github.com/MiSTer-devel/C64_MiSTer) (fixed commit
in `tools/fetch_c64.py`), adapted to Quartus Pro and Agilex 5.

- `vendor/` — original without ROMs, PLL and OPL3 firmware sources. **Not in
  the repository**; `python tools/setup.py` (or `tools/fetch_c64.py`) fetches it.
- `pro/` — adapted copies. Only the diffs are in the repository
  (`*.patch`, paths as in `vendor/`); `tools/apply_patches.py` generates
  the files from them.
- `rtl/` — own modules with testbenches in `tb/`: `iecdrv_bitmem.v`
  (1541 track buffer), `opl3_mem.v` (memory of the OPL3 emulation)
- `ip/pll_c64` — fixed PLL, `c64_de25.sdc` — timing
- `test/make_test_media.py` — test program, test disk and MGL (see below)

## Building

```
python tools/setup.py                # once: fetch third-party code, generate pro/
python tools/make_c64_roms.py        # ROMs from roms/ -> cores/c64/quartus/rtl/ (not in the repo)
python tools/make_core_qsf.py c64
Q:\tools\build_core.bat c64          # ~15 min; result quartus/output_files/c64.core.rbf
```

On the board: `c64.core.rbf` as `/media/fat/_Retro25/C64.rbf`. The `.rbf`
contains the ROMs from `roms/` — for personal use only, do not redistribute.
Utilization (as of 2026-10-22): 35,589 ALMs (76%), 222 M20K, timing met.

## Clock (PAL only, decision P4)

Fixed PLL: VCO 2837.5 MHz (50 · 227 / 4), clk64 = 63.0556 MHz (5.6 ppm off
MiSTer), clk_sys = clk64/2, clk48 (OPL) = 48.09 MHz, plus clk64 with +90° for
`SDRAM_CLK` via `sys/de25/ip/sdram_clk_ddio` (MiSTer's inverted clock does not
suit the 1.8 V SDRAM, see `cores/memtest/README.md`). No PLL is
reconfigured at runtime: the OSD option NTSC only switches the VIC timing, the
clock stays PAL (the drive would then run 3.8% too slow).

## ROMs

`tools/make_c64_roms.py` generates from `roms/` (names in `roms/README.md`):
BASIC+KERNAL and character set as `.mif`, the 1541 DOS (with MiSTer's 10-byte
patch, identical to its file) as `.hex`. There are no ROMs for C64GS, Japanese,
DolphinDOS and 1581: C64GS/Japanese read from the
standard ROM (saves 18 M20K), the 1581 has an empty ROM loadable via the OSD.

## Adaptations (overview)

- Patches from the predecessor project C64-DE25: SID, CIA (`mos6526.v`), parts of
  the 1541 drive.
- Quartus Pro pitfalls (table in `sys/de25/README.md`): nets assigned in
  `always` declared as `reg`/`logic`; identifiers before their
  declaration (implicit nets lose their assignment, warning 16788);
  registers with an initial value in the `always` block moved to module level (16754 — `static`
  does not help); VHDL `case` with `others`; `entity` before direct instantiation.
- Memory: in dual-port mode Agilex 5 cannot have two port widths and does not
  define the read result during a simultaneous write — track buffer and
  OPL3 memory rewritten (`rtl/`), otherwise `ramstyle = "no_rw_check"`.
  `ram_init_file = " "` (a space, "no file") crashes
  Quartus Pro — the drive ROMs are loaded by `$readmemh`.
- `sdram.v`: data register without clock enable (I/O register), no `altddio_out`.

## Testing on the board

```
python cores/c64/test/make_test_media.py          # writes to cores/c64/test/out/
scp cores/c64/test/out/* terasic@<board>:/media/fat/games/C64/
echo "load_core /media/fat/games/C64/retro25test.mgl" > /dev/MiSTer_cmd
```

The MGL loads the core, inserts the test disk and starts the program (it
starts by itself after loading). In the OSD the files are under "Mount #8"
and "Load PRG". (Under Git Bash, set `MSYS_NO_PATHCONV=1` for the second argument of
make_test_media.py, otherwise the path is turned into a Windows path.)
Status 2026-10-18:

| Test | Result |
|---|---|
| BASIC startup, RAM test in SDRAM | ok |
| Load and run PRG | ok |
| SID (noise generator, `$D41B`) | ok |
| Keyboard, OSD | ok |
| Disk write (file ends up correctly in the `.d64`) | ok |
| Disk read (including every sector of tracks 16–19 individually) | ok |
| Game from USB stick (`/media/usb0/C64`), sound over HDMI | ok |
| Joystick: gamepad on port 1, numeric keypad on port 2 (`joytest.mgl`), Nebulus playable with gamepad | ok |
| Cartridge (CRT type 0) 8 KB and 16 KB: startup code runs, ROM from `$8100` matches pattern (`crttest8k/16k.mgl`) | ok |
| Cartridge with bank switching (Magic Desk, type 19, 8 × 8 KB via `$DE00`, `crttestmd.mgl`) | ok |
| Tape (TAP v1, self-encoded, 6 KB incl. 4 KB pattern, `tapetest.mgl`): KERNAL LOAD ST=0, no read errors, data ok | ok |

The drive loads tracks in bursts starting at unaligned addresses. Bursts
crossing a 4 KB boundary violate AXI and arrived corrupted over F2SDRAM
(read errors 22/23 exactly at those sectors) — fixed in `sys` by
`avl_burst_4k` (see `sys/de25/README.md`).
The test cartridges bring their own startup code (signature `CBM80`) and check
every ROM byte against the pattern `address low XOR address high`; green border =
OK, red border = error. The 16 KB test also checks that EXROM/GAME are taken from
the CRT header (otherwise BASIC would be at `$A000`). CRT data
is stored in SDRAM from `0x200000`, not in DDRAM.
The Magic Desk test copies its check routine to `$C000` because otherwise it would
bank out its own code when switching. Note: MiSTer's
`cartridge.v` stores the banks in load order and addresses them directly
by bank number (the `lobanks` table is used only by EasyFlash) — CHIP packets
must appear in ascending order in the file (usual for real cartridges).
The tape test encodes a program itself in CBM format (like the
KERNAL write routine: dipoles short/medium, byte marker long+medium, odd
parity, two copies with countdown `$89…`/`$09…`, XOR checksum). The loader
`tapeload.prg` loads via KERNAL LOAD with messages and shows ST, the
error counters of both passes, end address and XOR sum. TAP data is stored in
SDRAM from `0x400000`. Two quirks of MiSTer's `tape_subsystem.sv`:

- A reset (including the one from loading a PRG with "Reset & Run") ejects the tape
  → in the MGL, first the PRG, then the tape; "Tape Auto Play" then presses
  PLAY.
- "Tape Auto Unload" ejects the tape already at the last counter step (~3 s before
  the end), even while it is playing. If the file ends right after the
  last block, the end of the second copy is missing (KERNAL: ST=$20,
  checksum error) → the test file has 10 s of trailing signal.

### Drive indicator

During drive accesses, e.g. "#8 12" appears in the bottom right (drive 8,
track 12; yellow = active). This is MiSTer's OSD option **Drives OSD**
(Activity Only = default, If Mounted, Debug, Off) — not an error.

### Setting up joysticks

Without a mapping file, Main recognizes neither the gamepad nor the numeric keypad as a
joystick — as with MiSTer, every device has to be defined once:

1. **Gamepad in the menu core:** F12 → System → "Define joystick buttons", first
   press a direction on the pad. Creates `config/inputs/input_<vid>_<pid>_v3.map`.
   Without this system mapping the pad gets no player number: Main
   only assigns a device to a player once a button appears in this
   mapping, and the fallback mapping uses Xbox codes (`0x130` …), which e.g.
   the Manta pad (`081f:e401`, codes `0x120`–`0x129`) never sends.
2. **In the C64 core:** F12 → "Define C64 buttons", for the pad and for the
   keyboard (numeric keypad 8/2/4/6, fire e.g. keypad 0; finish the rest with
   Enter). Creates `config/inputs/C64_input_<vid>_<pid>_v3.map`.
3. **Numeric keypad as joystick:** Num Lock cycles through mouse → joystick 1
   → joystick 2 → normal (message "Kbd mode: …"). The setting applies until
   the next core load.

The first gamepad becomes player 1 = port 1; swap ports in the OSD with
"Swap Joysticks". In the test program, port 1 also shows keys of
keyboard matrix column 7 (1, 2, CTRL, SPACE …) — that is not a joystick.
