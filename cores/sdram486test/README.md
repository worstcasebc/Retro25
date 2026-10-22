# sdram486test — SDRAM test for the z486 controller (P5 Z3)

Tests the z486's upstream SDRAM controller (`cores/z486/pro/src/memory/sdram.v`)
on the DE25-Nano's onboard SDRAM before the whole z486 runs on it.
Framework and display are taken from MiSTer's MemTest (`cores/memtest`).

## Files

| File | Purpose |
|---|---|
| `rtl/tester486.v` | Test sequence + upstream controller (85 MHz, `HAS_DQM=1`, 128 MB) |
| `rtl/sdram486test.sv` | `emu`: clocks, reset, display (derived from MemTest, GPL-2.0-or-later) |
| `core.tcl`, `sdram486test.sdc`, `build_id.v` | Project (`tools/make_core_qsf.py sdram486test`) |
| `make_variants.py` | one PLL per phase (`ip/pNNN/pll_486.ip`, via `ip-deploy`) and one revision `sdram486test_pNNN` |
| `../../tb/tb_tester486.v` | Testbench (Questa) with two chip models `tb/sdram_chip_model.v` |

Build: `python cores/sdram486test/make_variants.py`, then
`Q:\tools\build_core.bat sdram486test sdram486test_p090`.

## What is tested

One pass over the full 128 MB (both chips; `SDRAM_nCS2 = ~SDRAM_nCS` in
`sys_top_de25.v`, like MiSTer's 128 MB module):

1. write every dword in full — pattern `{~i[24:16], i[6:0], i[15:0]} ^ seed`
   (unique per address, both halves differ, `seed` changes with every
   pass)
2. overwrite one byte per dword via DQM (the byte lane alternates)
3. read everything back and compare: even passes as line reads (4 dwords
   with wrap from an alternating start dword, like the CPU's cache), odd
   passes as linear bursts of 8 dwords

Counted as errors: wrong dword, wrong number of responses, timeout.
One pass takes about 7 s at 85 MHz.

Display: top, run time (minutes) and `SDRAM_CLK` phase in degrees; middle,
`3` (= 128 MB) and passes (hex); bottom, errors (hex). OSD: "Reset Test".

## Testbench

`python tb/run_sim.py tb_tester486` — real controller, two chip models
(checking tRCD, tRP, tRC, tRAS, tRFC, command sequence, bank state). Result:
two passes without errors, both chips used equally often; a cross-check
with a flipped data bit in chip 1 counts exactly that chip's dwords as
errors.

## Results on the board (85 MHz, CL2, tRCD/tRP 2, tRC 6)

| SDRAM_CLK phase | Result (errors, hex) |
|---|---|
| 0° | error-free (2.5 min, 21 passes) |
| 45° | error-free (2.5 min, 21 passes) |
| 90° | error-free (10 min, 88 passes) |
| 135° | error-free (2.5 min, 21 passes) |
| 180° | marginal: ~0x39E00 errors in 21 passes (sporadic) |
| 225° | 0x2A000000 = every dword wrong in every pass |
| 270° | 0x2A000000 = every dword wrong |
| 315° | 0x29FFFFC0 = almost every dword wrong |

So the window is roughly 0°…135° (center ~67°). Chosen: **90°** — well
inside the window (≥ 45° = 1.5 ns margin to both edges) and the same phase
as for the C64 (`sdram_clk_ddio`), i.e. one setting for all cores.
Note: with 2.5 min per phase, "error-free" is only a rough indication; 90°
additionally ran for 10 min.
