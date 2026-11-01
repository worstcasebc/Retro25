# MegaDrive — MiSTer's MegaDrive_MiSTer (Nuked-MD) on the DE25

MiSTer's [Mega Drive / Genesis core](https://github.com/MiSTer-devel/MegaDrive_MiSTer)
(fixed commit in `tools/fetch_megadrive.py`), adapted to Quartus Pro and
Agilex 5. Fourth core of Retro25 (P6). Unlike the older Genesis_MiSTer it is
built on [Nuked-MD](https://github.com/nukeykt/Nuked-MD), a gate-level model
of the original chips (68000, Z80, VDP YM7101, FM YM3438, I/O and bus chips).

- `vendor/` — original without the Cyclone V PLL, images, `sim/`, `releases/`.
  **Not in the repository**; `python tools/setup.py` (or
  `tools/fetch_megadrive.py`) fetches it.
- `pro/` — adapted copies. Only the diffs are in the repository (`*.patch`,
  or `*.subst.json` search-and-replace rules); `tools/apply_patches.py`
  generates the files.
- `rtl/bram.vhd`, `rtl/mlab.vhd` — own replacements for MiSTer's files of the
  same name (same entities `spram`, `spram_sz`, `dpram`, `dpram_dif`,
  `dpram_difclk`, `mlab`), inferred RAMs instead of `altsyncram`; testbench
  `tb/tb_md_bram.v` (Questa).
- `rtl/vram_ip.v` — own replacement for `rtl/ram_md.v` (one VRAM bank,
  256 × 256 bit with byte enables) as a direct `altera_syncram`; testbench
  `tb/tb_md_vram_ip.v` (Questa with `altera_lnsim`).
- `ip/pll_md.ip` — fixed PLL, made with `tools/make_iopll.py`;
  `megadrive_de25.sdc` — timing

## Building

```
python tools/setup.py                # once: fetch third-party code, generate pro/
python tools/make_core_qsf.py megadrive
Q:\tools\build_core.bat megadrive    # result quartus/output_files/megadrive.core.rbf
```

On the board: `megadrive.core.rbf` as `/media/fat/_Retro25/MegaDrive.rbf`
(`linux/main/install.sh` uses this name), games in `/media/fat/games/MegaDrive`.

## Clock (NTSC only)

MiSTer reconfigures its PLL between NTSC and PAL. In Retro25 only `sys`
reconfigures a PLL, so the core has a fixed integer PLL: VCO 2362.5 MHz
(50 MHz × 189 / 4), `clk_sys` = 53.693182 MHz (C 44), `clk_md` =
107.386364 MHz (C 22), `CLK_VIDEO` = 53.693182 MHz, and `clk_md` with +45° for
`SDRAM_CLK`. NTSC needs 53.693175 MHz: the clock is 0.13 ppm off, which is
nothing. PAL games run at the NTSC clock (PAL 53.203424 MHz, so 0.9 % too
fast).

The SDRAM phase was measured with `cores/sdram486test` at exactly this
frequency and CL2 / tRCD 2: error-free window 315°…135°, chosen 45° (center),
see `cores/sdram486test/README.md`.

## Changes for Quartus Pro / Agilex 5

| Where | Why | Change |
|---|---|---|
| `MegaDrive.sv` | Cyclone V PLL with reconfiguration | fixed `pll_md`, `SDRAM_CLK` via `sdram_clk_ddio` (+45°) |
| `rtl/sdram.sv` | `inout` assigned in `always`; `altddio_out` (287078) | tri-state with `dq_out`/`dq_oe`; clock comes from `MegaDrive.sv` |
| `MegaDrive.qsf` macros | without `M68K_CHEAT`, `Z80_CHEAT`, `EXT_CLOCKS` ports behind `` `ifdef `` are missing (13305) | macros in `core.tcl` |
| `USER_OUT` | `emu` port (from `emu_ports.vh`) assigned in `always_comb` (13386) | one `assign` per bit |
| `rtl/bram.vhd` | `altsyncram` BIDIR with `clock1` (272006), mixed-width true dual-port, `init_file = " "` crashes | own file, see below |
| `rtl/ram_md.v` | inferred byte-enable RAMs are split into one RAM per byte: 8 × 32 RAMs of 256 × 8 bit, each a full M20K (444 of 358 blocks) | `rtl/vram_ip.v` with `altera_syncram` (252 blocks in total) |
| `mdp_audio.sv`, `nuked-md/68k.v` | `ramstyle = "M10K"` does not exist on Agilex 5 (272006) | `M20K` (subst rule) |
| `nuked-md/68k.v` | `$readmemb("68k_ucode.txt")` without a path is looked up next to the source — the `pro/` copy is elsewhere (13307) | path relative to the project (subst rule) |
| 17 registers | initial value inside `always` (16754, reset on every clock) — the reset counter stayed 0, **the core was held in reset** and synthesis removed most of the VDP | initial value removed (`port_core.py fix16754`) |
| 62 declarations | identifier used before `wire x = expr;` (16746/16788) — light gun mode and SNAC ports had no driver | `port_core.py fiximplicit` |
| `cartridge.sv`, `lightgun.sv`, `pad_io.sv` | `wire` assigned in `always` (13386) | `logic` |
| VM2413 (VHDL) | `'range` of an integer subtype; `case` without `others` | as in the NES |
| `rtl/cartridge.sv` | `.mif` path relative to MiSTer's project folder | `../vendor/rtl/mboot.mif` |

### RAM replacement (`rtl/bram.vhd`)

Three patterns that look like RAM were not recognized by Quartus Pro 26.1 for
Agilex 5 and became flip-flops (no error, only a huge design):

1. mixed-width port (8 / 16 bit) selecting the byte through a computed index
   — 128 KB cartridge SRAM as ~1 M flip-flops, synthesis ran for hours;
2. true dual-port with byte enables (Intel's template, word = array of bytes)
   — `ram_68k` (64 KB) as 524,288 flip-flops, 617,000 ALMs;
3. "new data" on read-during-write over 256 bit width — 26,000 LUTs of
   pass-through logic in the VRAM.

So `bram.vhd` builds every dual-port RAM from 8-bit banks without byte
enables (`dpram_same`; byte enable = write enable of the bank), the 8/16
cartridge SRAM from two such banks, and the VRAM uses `altera_syncram`
directly (`DONT_CARE` on read-during-write: `vram.v` never reads and writes
in the same cycle).

How the cause was found: synthesizing the parts on their own with a time
limit (each Nuked-MD chip, `md_board`, `emu`, the modules of `emu`, the
modules of `cartridge`) — all fast except `cartridge`, which pointed to the
RAM. See `docs/core-portieren.md`.

## Status

Runs on the board (2026-11-01). Build: 39,629 ALMs (85 %), 252 M20K (70 %),
50 DSP, timing met (worst setup slack 1.9 ns at `clk_md` 107 MHz),
`HPS IO hash` unchanged. Synthesis 2.5 min, full build 14 min.

| Test | Result |
|---|---|
| Sonic the Hedgehog (`.gen`): picture 320 × 224 at 59.9 Hz, demo, game | ok |
| Sound (FM and PSG) over HDMI | ok |
| Gamepad (default mapping) | ok |
| Virtua Racing (SVP, 2 MB, Europe — PAL timing at the NTSC clock): 3D title demo, menus, driving, sound | ok (no comparison with real hardware) |

Not tested yet: Master System games (`FS2,SMS`),
EEPROM / SRAM saves, light gun, MD+ / CD audio, other PAL games.

Test without a person at the board: MGL with the game
(`<file delay="1" type="f" index="1" path="/media/fat/games/MegaDrive/x.gen"/>`
— index 1 from `FS1,BINGENMD`), `load_core` on the MGL, then
`echo screenshot > /dev/MiSTer_cmd`.
