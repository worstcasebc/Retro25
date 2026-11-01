# NES — MiSTer's NES_MiSTer on the DE25

MiSTer's [NES core](https://github.com/MiSTer-devel/NES_MiSTer) (fixed commit
in `tools/fetch_nes.py`), adapted to Quartus Pro and Agilex 5. Third core of
Retro25 (P6) and the test case for how much work a MiSTer core port takes.

- `vendor/` — original without the Cyclone V PLL, `Palette/`, `releases/`.
  **Not in the repository**; `python tools/setup.py` (or `tools/fetch_nes.py`)
  fetches it.
- `pro/` — adapted copies of `NES.sv` and `rtl/sdram.sv`. Only the diffs are
  in the repository (`*.patch`); `tools/apply_patches.py` generates the files.
- `rtl/dpram.vhd` — own replacement for MiSTer's `rtl/dpram.vhd` (same
  entities `spram`, `spram_sz`, `dpram`), inferred RAMs instead of
  `altsyncram`; testbench `tb/tb_nes_dpram.v` (Questa).
- `ip/pll_nes.ip` — fixed PLL, made with `tools/make_iopll.py`;
  `nes_de25.sdc` — timing

## Building

```
python tools/setup.py                # once: fetch third-party code, generate pro/
python tools/make_core_qsf.py nes
Q:\tools\build_core.bat nes          # result quartus/output_files/nes.core.rbf
```

On the board: `nes.core.rbf` as `/media/fat/_Retro25/NES.rbf`, games in
`/media/fat/games/NES`.

## Clock (NTSC only, decision P6)

MiSTer reconfigures its fractional PLL at runtime between NTSC (85.909 MHz)
and PAL (85.126 MHz). In Retro25 only `sys` reconfigures a PLL (two
reconfigurable HVIO PLLs disturb each other), so the NES has a fixed integer
PLL: VCO 1890 MHz (50 MHz × 189 / 5), `clk85` = 85.909091 MHz (C 22, exact),
`CLK_VIDEO` = clk85/2, `clk` = clk85/4, plus clk85 with +90° for `SDRAM_CLK`.

With "System Type: PAL" the core switches to PAL timing, but the clock stays
NTSC: PAL games run 0.9 % too fast. Dendy and Vs. use the NTSC clock in
MiSTer, too.

## Changes for Quartus Pro / Agilex 5

| Where | Why | Change |
|---|---|---|
| `NES.sv` | fractional Cyclone V PLL + `pll_cfg` | fixed `pll_nes`, no reconfiguration |
| `rtl/sdram.sv` | `altddio_out` does not exist (error 287078); inverted clock does not suit the 1.8 V SDRAM | `SDRAM_CLK` = clk85 +90° via `sdram_clk_ddio` |
| `rtl/dpram.vhd` | `altsyncram` BIDIR_DUAL_PORT with `clock1` is rejected (272006); `init_file = " "` crashes Quartus Pro | own file with inferred RAMs |
| `NES.sdc` | clock names of the Cyclone V PLL | `nes_de25.sdc` with the same multicycle paths |
| EEPROM buffer in `NES.sv` | Agilex 5 M20K cannot do true dual-port with two clocks (error 22556) | port B clocked with `clk85` instead of `clk` (same PLL, `clk` = clk85/4, edges coincide) |
| package `regs_savestates` | only `ppu.sv` imports it at file level; Quartus Standard compiles all files as one unit, Pro each file on its own | package first in the file list, `import` in the 16 files that use it; `nes.v` as SystemVerilog |
| ~65 signals in 17 files | `wire`/untyped `output` assigned in `always` (error 13386) | `logic` |
| 110 + 62 declarations | identifier used before `wire x = expr;` (implicit net, assignment dropped: 16746/16788 — PPU, CPU decode, reset, savestates had no driver) | declaration moved to the start of the module, `assign` at the old place |
| 10 registers | initial value inside `always` (16754, reset on every clock) | initial value removed or register moved to module level |
| `SDRAM_DQ` | `inout reg` assigned in `always` | tri-state with `dq_out`/`dq_oe`, data register loaded every cycle (as in the menu core) |
| VM2413 (VHDL) | `'range` of an integer subtype; `case` on `std_logic_vector` without `others` | `array (ch_type)`; last choice → `when others` |
| `rtl/tao.mif`, `rtl/loopy_NSF.mif` | paths relative to MiSTer's project folder; `SEARCH_PATH` does not resolve `rtl/…` | `../vendor/rtl/…` |

Most of these changes were found and applied with small scripts working on
the Quartus report (13386, 16746/16749, 16754): the same patterns will show
up in every MiSTer core, see `docs/core-portieren.md` (P6, N5).

Note: VM2413 contains Shift-JIS comments; `tools/apply_patches.py` passes
non-UTF-8 sources through byte for byte.

## Status

Runs on the board (2026-11-01). Build: 39,879 ALMs (85 %), 90 M20K, 72 DSP,
timing met, `HPS IO hash` unchanged. Needs Main with patch 0011 (savestates
via `shmem_put`; before, Main crashed with SIGBUS when a game was loaded).

| Test | Result |
|---|---|
| Super Mario Bros (mapper 0), sound, gamepad | ok |
| Savestates: save to / restore state 1 (`savestates/NES/*.ss`) | ok |
| Super Mario Bros. 3 (MMC3) | ok |
| Zelda II (MMC1) | ok |
| Battery RAM: name registered, `saves/NES/Zelda II.sav` written when the OSD opens, name still there after reloading | ok |

Not tested yet: FDS (needs the disk system BIOS), PAL games (run 0.9 % too
fast by design, see above).

Test without a person at the board: MGL with the game
(`<file delay="1" type="f" index="0" path="/media/fat/games/NES/x.nes"/>`),
`load_core` on the MGL, then `echo screenshot > /dev/MiSTer_cmd`. A grey
screen means the PPU runs but no cartridge is loaded.
