# Memtest — SDRAM test (MiSTer's MemTest on the DE25)

Tests the DE25's 128 MB SDRAM (1.8 V, two chip selects; as on MiSTer, the
first chip, 64 MB, is tested) with MiSTer's
[MemTest](https://github.com/MiSTer-devel/MemTest_MiSTer). Used in P4 to
determine the SDRAM clock for the C64.

- `vendor/` — original, unmodified, not in the repository (`python tools/setup.py` or `tools/fetch_memtest.py`)
- `pro/` — adapted copies for Quartus Pro/Agilex 5; only the diffs `pro/*.patch` are in the repository (`tools/apply_patches.py` generates the files)
- `ip/pll_memtest` — fixed PLL: 64 MHz (like the C64's clk64) and the same
  frequency with +90 degrees for `SDRAM_CLK`; `ip/pll_memtest_vid` — 27 MHz video
- Build: `python tools/make_core_qsf.py memtest`, then `Q:\tools\build_core.bat memtest`

## Operation and display

In the menu (F12) under `_Retro25` as `Memtest`. Screen from top to bottom:

| Line | Color | Contents |
|---|---|---|
| 1 | yellow | Run time in minutes, frequency in MHz (fixed 064) |
| 2 | cyan / green | Memory size (2 = 64 MB) / passes completed (hex, 32 MB each) |
| 3 | red | **Errors** (hex, number of 16-bit values read incorrectly) — passed at 0 |

Enter resets the test. Changing the frequency and auto mode (keys
up/down, A) have no effect here: only `sys` may reconfigure a PLL at
runtime (two reconfigured HVIO PLLs interfere with each other, see
`sys/de25/README.md`); every frequency is a separate build.

Remotely (Main accepts commands via `/dev/MiSTer_cmd`):

```
echo "load_core /media/fat/_Retro25/Memtest.rbf" > /dev/MiSTer_cmd
echo screenshot > /dev/MiSTer_cmd     # PNG in /media/fat/screenshots/MEMTEST/
```

## Changes (pro/)

- **memtest.sv:** fixed IOPLL instead of the reconfigurable Cyclone V PLL
  including `pll_cfg`; SDRAM clock from the second PLL output via the DDIO
  register `sys/de25/ip/sdram_clk_ddio` (`din = 2'b10`: clock unchanged);
  fixed frequency display; auto mode off; pitfall 16754 (register with
  initial value in an always block).
- **sdram.v:** `inout reg` → tri-state with `dq_out`/`dq_oe`; `dq_out`
  without clock enable (otherwise the data and output-enable registers do
  not fit into the I/O cell together, Fitter errors 14996/24403);
  `altddio_out` removed (`DRAM_CLK` unused); pitfall 16754.
- **tester.v:** pitfall 16754 — otherwise the test never starts.

## Measurements (P4, 2026-10-17)

All with I/O registers for address, commands and data (`FAST_*_REGISTER`
in `sys/de25/sys_de25.tcl`, as on MiSTer) and the SDRAM clock via the DDIO
register. 1.5–5 min each; when there are errors, the counter is huge after
just seconds (practically every value read is wrong).

| Frequency | SDRAM_CLK phase | Result |
|---|---|---|
| 64 MHz | 0° | almost everything wrong |
| 64 MHz | 45° | error-free |
| 64 MHz | **90°** | **error-free** (25 min, 707 passes) |
| 64 MHz | 135° | error-free |
| 64 MHz | 180° (inverted, as on MiSTer) | almost everything wrong |
| 64 MHz | 270° | almost everything wrong |
| 100 MHz | 0° | error-free (5 min) |
| 100 MHz | 180° | almost everything wrong |

Without the I/O registers, 100–140 MHz with 180° also failed (earlier
measurement).

**Interpretation:** MiSTer's controller reads the data after a fixed number
of clock cycles. On MiSTer (Cyclone V, 3.3 V SDRAM) this fits the inverted
clock. On the DE25 the read data arrives later (1.8 V SDRAM and pins) — at
64 MHz the valid window lies between roughly 45° and 135°. The right phase
depends on the frequency because the propagation delays are fixed times
(64 MHz: 90° = 3.9 ns; 100 MHz: 0° works, 180° does not). Terasic's SDRAM
demo also generates `DRAM_CLK` from a PLL output with a phase shift.

**Consequence for the C64 (decision 2026-10-17):** an additional output of
the C64 PLL, clk64 with +90°, via `sdram_clk_ddio` (`din = 2'b10`) to
`SDRAM_CLK` instead of the inverted clk64. Its controller may sample in a
different cycle than the Memtest — the phase is verified with the C64
itself.
