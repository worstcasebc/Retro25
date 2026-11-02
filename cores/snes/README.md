# SNES — MiSTer's SNES_MiSTer on the DE25

MiSTer's [SNES core](https://github.com/MiSTer-devel/SNES_MiSTer) by srg320
(fixed commit in `tools/fetch_snes.py`), adapted to Quartus Pro and Agilex 5,
including the cartridge chips (DSP-1…4, CX4, GSU/SuperFX, SA-1, SDD-1,
SPC7110, OBC1, S-RTC, BSX, Sufami Turbo, MSU-1). Fifth core of Retro25 (P6).

- `vendor/` — original without the Cyclone V PLL, `hw/`, `smpsim/`, `src/`,
  `releases/`. **Not in the repository**; `python tools/setup.py` (or
  `tools/fetch_snes.py`) fetches it. The `.mif` files under `rtl/chip/` are
  dumps of the original chip ROMs: they stay in `vendor/` only.
- `pro/` — adapted copies. Only the diffs are in the repository (`*.patch`,
  or `*.subst.json` search-and-replace rules); `tools/apply_patches.py`
  generates the files.
- `rtl/bram.vhd` — own replacement for MiSTer's `rtl/bram.vhd` (same
  entities `spram`, `spram_sz`, `dpram`, `dpram_dif`, `dpram_difclk`),
  derived from `cores/megadrive/rtl/bram.vhd`; testbench `tb/tb_snes_bram.v`
  (Questa). `rtl/mlab.vhd` — same as the MegaDrive one (MiSTer's originals
  are identical).
- `ip/pll_snes.ip` — fixed PLL (`tools/make_iopll.py`); `snes_de25.sdc` —
  timing

## Building

```
python tools/setup.py                # once: fetch third-party code, generate pro/
python tools/make_core_qsf.py snes
Q:\tools\build_core.bat snes         # result quartus/output_files/snes.core.rbf
```

On the board: `snes.core.rbf` as `/media/fat/_Retro25/SNES.rbf`
(`linux/main/install.sh` uses this name), games in `/media/fat/games/SNES`
or on a USB stick in `games/SNES`.

## Clock (NTSC only)

The same clocks as the NES: VCO 1890 MHz (50 MHz × 189 / 5), `clk_mem` =
85.909091 MHz (C 22), `CLK_VIDEO` = 42.95 MHz, `clk_sys` = 21.477273 MHz
(MiSTer NTSC: 21.47727), plus `clk_mem` with +90° for `SDRAM_CLK` (the phase
measured for 85 MHz, `cores/sdram486test`). MiSTer switches its PLL to
21.28137 MHz for PAL; here PAL games keep the NTSC clock and run 0.9 % too
fast.

## Changes for Quartus Pro / Agilex 5

| Where | Why | Change |
|---|---|---|
| `SNES.sv` | Cyclone V PLL + `pll_cfg` | fixed `pll_snes`, `SDRAM_CLK` via `sdram_clk_ddio` (+90°) |
| `rtl/sdram.sv` | `inout reg` in `always`; `altddio_out` (287078) | tri-state with `dq_out`/`dq_oe`; clock from `SNES.sv` |
| `rtl/sdram.sv` | `reg [4:0] reset = 5'h1f` inside `always` (16754): reset on every clock, **the SDRAM would never finish its init** | register moved to module level |
| `USER_OUT` | `emu` port assigned in `always_comb` (13386) | helper `SNAC_OUT`, one `assign` per bit |
| `rtl/main.v` | uses `do` as a signal name — a SystemVerilog keyword; Quartus Pro reads `.v` files with SV keywords (19645) | `-hdl_version VERILOG_2001` in `core.tcl` |
| `rtl/main.v` | `output reg SNI_JOY` driven by an instance (13458) | `output wire` |
| `rtl/main.v` | 16 save-state nets first used **inside `generate` blocks**, declared later: Quartus Pro creates separate implicit nets in the generate scope (16788 without the usual 16746 warning) — DSP/CX4/GSU save states had no driver | declarations moved to the start of the module |
| `chip/DSP/DSP_LHRomMap.vhd` | Verilog `1'b1` passed to a VHDL generic of type `std_logic` arrives as `'X'`: `if USE_DSPn = '1' generate` was false, **the DSP-1 was missing** (Super Mario Kart hung at the Nintendo logo) | generic as `integer` |
| `CPU.vhd` | `case` on `std_logic_vector` without `others` (13630) | last choice → `others` |
| `chip/CX4/CX4Map.vhd`, `chip/DSP/DSPn.vhd` | `and`/`or` with operands of different length (22 vs 23, 11 vs 8 bit; 13825) | shorter operand zero-extended (value-aligned) |
| `.mif` paths (DSP-1, CX4, BSX) | relative to MiSTer's project folder | `../vendor/rtl/chip/…` |
| ~10 files | 13386, 16754, implicit nets (16746/16788) | `port_core.py fix13386`, `fix16754`, `fiximplicit` |

### RAM replacement (`rtl/bram.vhd`)

Same approach as the MegaDrive (8-bit banks instead of byte enables, two
banks for 8/16 and 16/32 bit ports), plus:

- **widths that are not a multiple of 8** (CGRAM 15 bit, sprite buffer 9 bit):
  one memory in full width;
- **dual-port RAM with a `.mif`** (BSX);
- **ROMs from a `.mif` read with a registered output** (`q <= rom(addr)`).
  With a registered address and a combinational read Quartus Pro turned the
  never-written tables into logic, even with `ramstyle "M20K"`: DSP-1 and CX4
  took 5,600 LUTs (97 % instead of 88 %);
- **no `mod numwords`**: with a depth that is not a power of two (DSP-1: 8096,
  7168 words) it became a divider; the memory now has the full depth;
- **`ram_init_file` only with a real file**: `" "` crashes Quartus Pro
  (`osi_sys.c`, "required_unc_path_size");
- **`dpram_difclk` where both ports write** (CX4 data RAM: CX4 on `not CLK`,
  SNES CPU on `CLK`). Agilex 5 cannot build a true dual-port RAM with two
  clocks (22556). All writes happen on port A's clock (a port B write half a
  cycle later), and there are two copies for reading — one per port, each a
  simple dual-port RAM. Costs a few M20K; only valid for two clocks from the
  same source (equal or inverted).

## Status

Runs on the board (2026-11-01). Build: 40,987 ALMs (88 %), 305 M20K (85 %),
42 DSP, timing met (worst setup slack 1.7 ns at `clk_mem` 86 MHz),
`HPS IO hash` unchanged. Synthesis 3 min, full build 15 min. With
`vsync_adjust=1` the HDMI output follows the core's 60.1 Hz.

| Game | Chip | Result |
|---|---|---|
| Super Mario World | – | ok (title, demo) |
| The Lost Vikings 2 | – | ok (played) |
| Super Mario Kart | DSP-1 | ok (played) |
| Mega Man X2 | CX4 | ok (played) |
| Star Fox | GSU (SuperFX) | ok (played) |
| Super Mario RPG | SA-1 | ok (played, battery save written and reloaded) |

Not tested yet: save states, SDD-1, SPC7110, BSX, MSU-1,
PAL games.

Test without a person at the board: MGL with the game
(`<file delay="1" type="f" index="1" path="/media/usb0/games/SNES/x.sfc"/>`
— index 1 from `FS1,SFCSMCBINBS`), `load_core` on the MGL, then several
`echo screenshot > /dev/MiSTer_cmd` a while apart (many games show a black
screen between logos).
