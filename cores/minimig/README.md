# Amiga — MiSTer's Minimig-AGA on the DE25

MiSTer's [Amiga core](https://github.com/MiSTer-devel/Minimig-AGA_MiSTer)
(fixed commit in `tools/fetch_minimig.py`), adapted to Quartus Pro and Agilex 5.
It emulates the Amiga chipset up to AGA, so it can run as an A500, A600 or
A1200. Sixth core of Retro25 (P6). The commit matches the Main_MiSTer commit,
since core and Main share the Minimig protocol.

- `vendor/` — original without the Cyclone V PLL, `sys/`, `rtl/sim/`,
  `releases/`. **Not in the repository**; `python tools/setup.py` (or
  `tools/fetch_minimig.py`) fetches it.
- `pro/` — adapted copies. Only the diffs are in the repository (`*.patch`);
  `tools/apply_patches.py` generates the files.
- `rtl/bram.vhd`, `rtl/denise_colortable_ram_mf.v` — own inferred replacements
  for MiSTer's `altsyncram` RAMs; testbench `tb/tb_minimig_ram.v` (Questa).
- `ip/pll_minimig.ip` — fixed PLL; `minimig_de25.sdc` — timing, translated from
  MiSTer's `Minimig.sdc`

## Building

```
python tools/setup.py                   # once: fetch third-party code, generate pro/
python tools/make_core_qsf.py minimig
Q:\tools\build_core.bat minimig         # result quartus/output_files/minimig.core.rbf
```

31,282 ALMs (67 %), 186 M20K, 53 DSP. Timing is met, with +1.7 ns setup slack
at 113.5 MHz. This build includes CD32, CDTV, Toccata and A2065, which were not
removed.

## On the board

`minimig.core.rbf` goes to `/media/fat/_Retro25/Minimig.rbf` (`install.sh` uses
this name). Everything else is in `/media/fat/games/Amiga/`:

| File | What |
|---|---|
| `a1200.rom` | Kickstart 3.1 for the A1200, your own copy. **Lower case**: Linux distinguishes it, and the A1200 preset looks for this exact name |
| `*.adf` | floppy images |
| `*.hdf` | hard disk images |

Kickstart ROMs and Workbench disks are copyrighted and never go into the
repository. Amiga Forever and Hyperion sell licensed copies.

**First start:** F12 → load preset → `A1200 AGA ChipRAM 2MB`, then save the
configuration in the OSD. Without a configuration the core starts as an A500
with `KICK.ROM`.

**Empty hard disk:**

```
$ truncate -s 500M /media/fat/games/Amiga/Amiga.hdf
```

In the OSD (CD & HDD) enable IDE and select the file. Boot from the Install
disk, partition with `HDSetup` or `HDToolBox`, and format. Then run
`Install`.

- Choose the **hard disk partition** as the target. A floppy called
  `WorkBench3.1` looks much like a partition called `Workbench`. Installing
  onto the floppy ends at 12 % with "object in use" and changes the image.
- Put the disks the installer asks for into `df1` and leave the Install disk in
  `df0`.
- AmigaDOS writes to `.adf` files. Keep untouched copies of your images.

## Clock (PAL only)

VCO 2270 MHz (50 MHz × 227 / 5), `clk_114` = 113.5 MHz (C 20), `clk_sys` =
28.375 MHz (C 80). MiSTer: 113.50064 and 28.37516 MHz. MiSTer switches its PLL
to NTSC at runtime; in Retro25 only `sys` reconfigures a PLL, so the clock stays
PAL. An NTSC chipset setting runs 0.9 % too slow.

## SDRAM

The core generates `sd_clk` in logic (`sdram_state[0]`, 56.75 MHz), and the
signals change one `clk_114` cycle before the rising edge. That is about the
+90° the 1.8 V SDRAM needs, so this core does **not** use `sdram_clk_ddio`. The
timing analysis does not cover the SDRAM pins. The evidence is from the board:
Kickstart runs from SDRAM, and a Workbench installation copied 331 files
byte-identically from floppy to hard disk.

## Changes for Quartus Pro / Agilex 5

| Where | Why | Change |
|---|---|---|
| `Minimig.sv` | Cyclone V PLL + `pll_cfg` | fixed `pll_minimig`, reconfiguration removed |
| `rtl/sdram_ctrl.v` | `inout reg` in `always` (13386) | tri-state with `dq_out`/`dq_oe` |
| `rtl/bram.vhd` | MiSTer's `altsyncram` | own `dpram`, inferred in full width, single clock |
| `rtl/denise_colortable_ram_mf.v` | byte enables split a RAM per byte | two 16-bit banks; Denise only writes `0011` or `1111` |
| `rtl/fx68k/fx68k.sv`, `rtl/akiko_nvram.v` | `$readmem`/`.mif` paths relative to MiSTer's project folder (13307) | `../vendor/rtl/…` |
| `rtl/fpga-toccata/toccata_fifo.sv` | `ramstyle = "M10K"` (272006) | `M20K` |
| ~15 files | 13386, 16754, implicit nets (16746/16788) | `port_core.py fix13386`, `fix16754`, `fiximplicit` |
| `core.tcl` | `mt32pi` as a black box (19636) | `sys/vendor/mister/mt32pi.sv` added |

Remaining 16788 warnings, unchanged from upstream: `leadlag[1]` in
`MiSTerFloppyPLL` (never driven) and `cap.rd` in Toccata.

## Status

Tested on the board: Kickstart 3.1, Workbench 3.1 from floppy and from hard
disk, floppy read and write, disk change, partitioning, formatting, keyboard,
mouse including the right button, sound (beep in `Prefs/Sound`). HDMI locks at
49.92 Hz with `vsync_adjust=1`.

Open:

- no long run under load, no games or demos yet
- not tested: CD32, CDTV, RTG graphics, Toccata, MIDI, MiSTer Floppy
- no network: the A2065 mailbox at `0x1FF00000` is outside the DDR window
- Main still uses `unsigned long` in the old configuration format in
  `support/minimig/minimig_config.cpp` (8 bytes on aarch64). Current
  configurations are unaffected; old configuration files from a 32-bit MiSTer
  may not load
- Quartus warns once that a ROM has depth 336 but a 512-entry init file
  (127004); not traced, no visible effect
