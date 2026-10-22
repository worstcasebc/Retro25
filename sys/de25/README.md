# sys/de25 — MiSTer's framework on the DE25-Nano

MiSTer's `sys/` (unmodified in `sys/vendor/mister`, fetched by `tools/setup.py`) is written for the Cyclone V of the
DE10-Nano. This directory holds the replacement parts for the Agilex 5 of the
DE25-Nano. Goal: every MiSTer core (`module emu`, `sys/emu_ports.vh`,
`hps_io`) runs on it unmodified; only its PLL is regenerated as an Agilex
IOPLL.

## Files

| File | Purpose |
|---|---|
| `sys_top_de25.v` | Top level, derived from `sys_top.v` (changes marked with "DE25:") |
| `hps_gp_bridge.v` | gp_out/gp_in of the Cyclone V HPS as registers on the LW bridge (`0x2001_0100`) |
| `sysmem_de25.v` | Replacement for `sysmem_lite`: clock, reset, three DDR ports (vbuf/ram1/ram2) to F2SDRAM, addresses into the window `0xA000_0000` |
| `avl_burst_4k.v` | splits Avalon bursts at 4 KB boundaries (AXI rule of the F2SDRAM), behind each `f2s_halt_de25` |
| `f2s_halt_de25.v` | cleanly halts a DDR port before reconfiguration (one instance per port in `sysmem_de25`); register `0x2001_7000` for Main (`p3/linux/f2s_halt.py`) |
| `hps_bridges.tcl` | qsys script: Avalon bridges `c64_m0` (gp registers) and `disk_m0` (other registers) on the LW bridge, as done by hand in the C64 project (applied first by `tools/fetch_hps.py`) |
| `hps_f2sdram_ports.tcl` | qsys script: three Avalon ports (Clock Crossing Bridges) in `qsys_top` (applied by `tools/fetch_hps.py`) |
| `hps_slim.tcl` | qsys script: removes GHRD demo and debug parts, disables the FPGA→HPS bridge (P5, see below; applied afterwards by `tools/fetch_hps.py`) |
| `video_debug.v` | Measurement points of the video chain, Linux reads them at `0x2001_4000` (`p3/linux/video_debug.py`) |
| `ip/pll_hdmi_de25.ip` | HDMI PLL (HVIO IOPLL with reconfiguration port), initial value 148.5 MHz |
| `pll_cfg_de25.v` | Replacement for `pll_cfg`: takes Main's PLL registers (Cyclone V format) and reconfigures the IOPLL via `core_avl_*`; debug registers at `0x2001_5000` (`p3/linux/pll_cfg.py`) |
| `i2c_master_de25.v` | byte-wise I2C master for the HDMI transmitter, Linux at `0x2001_6000` (Main: `linux/main/de25/smbus.cpp`, test: `p3/linux/i2c_test.py`) |
| `avl_slow_cdc.v` | carries single LW bridge accesses from `clk_100` into the CLOCK0_50 domain |
| `pro/*.sv`, `pro/*.v` | copies of MiSTer files adapted for Quartus Pro (not in the repository; `tools/apply_patches.py` generates them from `sys/vendor` and the `*.patch` files) (see below); since the C64 also the video helper modules that cores instantiate themselves (`video_mixer`, `hq2x`, `gamma_corr`, `video_cleaner`, `arcade_video`) |
| `hdmi_config.v`, `i2c_write.v` | configure the ADV7513 HDMI transmitter (from C64-DE25) until Main has taken over the bus (picture even without Main) |
| `sync_2ff.v` | Synchronizer |
| `ip/sdram_clk_ddio.ip` | DDIO output register (GPIO IP) for `SDRAM_CLK`: `din[1]` while the clock is high, `din[0]` while low — `2'b10` outputs the clock 1:1 (see P4 below) |
| `ip/pll_audio.ip` | 24.576 MHz for audio (50 MHz × 29 / 59 = 24.57627 MHz, +11 ppm) |
| `sys_de25.tcl` | common Quartus settings and pins of all cores |
| `sys_top_de25.sdc` | Timing constraints |

A core project is created with `python tools/make_core_qsf.py <core>` from
`sys_de25.tcl` and `cores/<core>/core.tcl`; it is built with
`Q:\tools\build_core.bat <core>`.

## What differs from the DE10-Nano

| Topic | DE10-Nano (Cyclone V) | DE25-Nano |
|---|---|---|
| gp_out/gp_in | registers in the HPS | `hps_gp_bridge` on the LW bridge, writes with handshake |
| DDR access (ascal, DDRAM, ALSA) | 3 × fpga2sdram | 3 Avalon bridges → AXI4 F2SDRAM, window `0xA000_0000–0xBFFF_FFFF` (P3) |
| HDMI transmitter setup | Main_MiSTer via HPS I2C | Main via `i2c_master_de25` (LW bridge); `hdmi_config` before that |
| HDMI PLL | fractional, `pll_cfg` + `pll_hdmi_adj` | integer only: Main computes N/M/C (patch `0004`), `pll_cfg_de25` translates; without `pll_hdmi_adj` (low-latency adjustment, `vsync_adjust=2`) |
| HDMI clock at the pin | DDIO output | direct; output registers on the falling edge |
| Analog VGA, I/O board, user port, SD SPI, ADC | present | not available (inputs tied to fixed values) |
| UART/MIDI, ALSA, interrupts to the HPS | HPS peripherals | not connected yet |
| SDRAM | module 3.3 V, one chip select | onboard 128 MB, **1.8 V**, two chip selects (`SDRAM_nCS2 = ~SDRAM_nCS`, like MiSTer's 128 MB module; cores with 32 MB keep nCS=0) |
| SDRAM clock | inverted core clock via `altddio_out` | PLL output with phase shift via `sdram_clk_ddio` (+90° at 64 MHz, P4) |
| Core PLLs | may be reconfigured at runtime (`pll_cfg`) | fixed — only `sys` reconfigures a PLL (HDMI) |
| LEDs | active high | active low (`LEDR`) |
| 50 MHz clocks | FPGA_CLK1/2/3_50 | CLOCK0/2/1_50 (mapped in this order) |

## Status P1 (done 2026-10-15)

Verified on the board: `testpattern.core.rbf` loaded via `p0_switch.py`,
`gp_check.py` reads the ID and `io_ver` over the bridge, HDMI shows the
test pattern. Important: after loading, `sys_top` holds the core in reset until
gp_out[31:30] signals the release (done by `gp_check.py`, later by Main_MiSTer).
Also: MiSTer's direct video reconstructs DE from the syncs (for VGA adapters); the
HDMI transmitter needs the core's real DE — changed in `sys_top_de25.v`.

Direct video only (`MISTER_DEBUG_NOHDMI`): the core's picture goes to the HDMI
transmitter with the core's own clock. This only works for cores with
standard-compliant timing — that is what the test core `cores/testpattern` (720p60) is for. Real
MiSTer cores need the `ascal` scaler and therefore DDR (P3).

## Status P3: scaler (step 3, 2026-10-15)

`MISTER_DEBUG_NOHDMI` is off: the core's picture goes through `ascal` and a
triple buffer in the HPS DDR (`0xA000_0000`) to the HDMI transmitter. Main sends the
output timing (command `0x20`); Main's screenshot (`echo screenshot >
/dev/MiSTer_cmd`) reads the same buffer. `direct_video=1` is not yet
supported (no clock switch).

Verified on the board: test pattern through the scaler, OSD via F12 at full
size (doubled), Main measures the core output as 1280 × 720,
60 Hz, 74.25 MHz. The HDMI PLL (`ip/pll_hdmi_de25.ip`) is still fixed at
74.25 MHz; runtime switching follows in step 4.
`video_debug.v` (measurement points of the video chain, 0x2001_4000, read with
`p3/linux/video_debug.py`) stays in the design as a tool.

## Status P3: HDMI PLL and HDMI transmitter via Main (step 4, 2026-10-16)

**PLL:** The Agilex 5 IOPLL divides by integers only: Fpix = 50 MHz · M / (N · C).
Main searches N (1..5, PFD ≥ 10 MHz), M (up to 320) and C such that the VCO is
600..3200 MHz and the deviation is minimal, and sends the values as
before in Cyclone V format. `pll_cfg_de25` translates them into the sequence from the
manual (Clocking and PLL User Guide 813671, sections 6.2/6.3): enable
registers, clear calibration status, M/N (0x40), charge pump according to M (0x44),
C0 (0x5C), reset pulse (0x80), enable calibration (0x48) and request it
(0x88), wait for lock. Takes about 1 ms. Measured on the board:
1280×720 (74.25 MHz), 1920×1080 (148.5), 1024×768 (65), 640×480 (25.175,
+17 ppm) via `video_mode`; picture and OSD at 1080p confirmed by the user.

Findings on the IOPLL port (ambiguous in the manual, clarified on the board):
serial devices address words (byte offset >> 2); a 32-bit register
is transferred as 4 bytes, LSB first. Write: 10 cycles `write`, 5 × 0x00, then
b0 b1 b2 b3 b3. Read: the data arrives from the first cycle on as
`00 b0 b1 b2 b3`, twice in a row.

**HDMI transmitter:** instead of `/dev/i2c-N`, Main uses the I2C master in the FPGA
(`linux/main/de25/smbus.cpp`, same interface `smbus.h`). On first
open, Main takes over the bus (`own`); until then `hdmi_config` configures the
ADV7513, so a picture appears even without Main. Main reads chip ID and
EDID and writes its own initialization.

**Placement:** only HVIO IOPLLs have the `core_avl_*` port. Which kind an
IOPLL becomes is decided by its reference clock: CLOCK0_50 (`FPGA_CLK1_50`) sits in
an HSIO bank and yields an IO96B PLL. Therefore `pll_hdmi` is driven by
CLOCK1_50 (`FPGA_CLK3_50`, HVIO) and `pll_audio` by CLOCK0_50 — unlike
MiSTer. `pll_audio` is locked to `IOPLL_X63_Y0_N0`: in the IO96B
bank of the HPS memory (X63_Y53) it changed the HPS IO hash.

**Only sys reconfigures a PLL (rule since P4):** the memtest reconfigured its
own HVIO PLL at runtime while `pll_cfg_de25` was setting the HDMI PLL.
Two HVIO PLLs reconfigured at the same time interfere with each other: writes
were lost, reads returned wrong values, the HDMI picture stayed black.
Therefore cores have fixed PLLs; a different frequency is a separate build.

**Read in once instead of read-modify-write:** right after loading, the IOPLL
port answers only with 0xFF for a while. `pll_cfg_de25` therefore waits
after reset for lock plus 1 ms (`INIT_DELAY`), then reads the eight
registers involved (0x10, 0x58, 0x40, 0x44, 0x5C, 0x80, 0x48, 0x88), each
twice until two identical values arrive, and never accepts 0xFFFFFFFF. After that
it only writes from this stored state (other bits are
preserved), verifies 0x40/0x44/0x5C as full words after writing, and
retries on mismatch after a 1 ms pause, up to 8 attempts. Status bit 3 =
verify error, bits 31:24 = number of retries (`p3/linux/pll_cfg.py`).
On the board: all modes clean, 0 retries. Testbench with fault model
(lost writes, wrong read values, "not ready").

## Status P3: core switching with DDR traffic (step 5, 2026-10-16)

If the FPGA is reconfigured while a burst is in progress over F2SDRAM or
read data is in flight, the HPS side waits forever for the rest. On the
Agilex 5 the SMMU then hangs (`arm-smmu-v3 … CMD_SYNC timeout`), and with it
all devices using DMA and finally Linux. MiSTer has the same problem on
the Cyclone V (`f2sdram_safe_terminator`; there "only" the next core hangs).

`f2s_halt_de25` sits between each Avalon master (ascal, the core's DDRAM,
ddr_svc) and its port to `qsys_top`:

- **halt** (from Main, register `0x2001_7000` bit 0): stop the master at a
  command boundary — a write burst already started runs to completion,
  a pending command stays until it is accepted.
- **takeover** (ram1 only, on the core's system reset): finish writing the burst
  cut off by the reset itself (byteenable = 0), like MiSTer's
  terminator.
- **idle** (bits 3:1): halted, all read data returned, followed by 1024 cycles
  of quiet (write responses behind the Clock Crossing Bridge). A port that
  has never been accessed since loading (e.g. without a clock) counts as empty.

Main (`linux/main/de25/fpga_io.cpp`) sets `halt` before every load and waits
at most 0.5 s for `idle` (measured: under 0.1 ms); otherwise it does not load.

**Limitation:** `sys` does not see a reset *inside* the core. If a
core aborts a DDRAM burst that way, Linux still hangs — this happened with
`ddr_test` in the testpattern core (Main sets `status[0]` several times at startup).
**Rule for every core:** complete DDRAM bursts even during reset.

## SDRAM (P4, 2026-10-17)

- **I/O registers:** as in MiSTer, `sys_de25.tcl` sets `FAST_OUTPUT_REGISTER`
  on all `SDRAM_*`, `FAST_OUTPUT_ENABLE_REGISTER` and `FAST_INPUT_REGISTER`
  on `SDRAM_DQ[*]`, and `ALLOW_SYNCH_CTRL_USAGE OFF`. MiSTer cores have
  no I/O timing in the `.sdc`; they rely on short, equal
  register↔pin delays. Check in the Fitter report (pin tables, columns
  "Input/Output Register") that they are set.
- **Data and output-enable registers share one clock enable** in the
  I/O cell: if the data register is only loaded on writes
  (`if (we) dq_out <= …`) but the output-enable register on every cycle, the
  Fitter finds no placement (errors 14996/24403). Fix: load the data register on
  every cycle — at the pin it only takes effect when the enable is set
  (`cores/memtest/pro/sdram.v`, `cores/menu/pro/sdram.sv`).
- **Clock:** MiSTer's inverted clock (180°) does not suit the DE25's 1.8 V SDRAM
  — at 64 MHz almost every read value came back wrong. Error-free are
  45–135° (measurements in `cores/memtest/README.md`). Cores therefore generate
  `SDRAM_CLK` from a dedicated PLL output with phase shift and output it
  via `ip/sdram_clk_ddio` (`din = 2'b10`); the right phase depends on
  the frequency.

## Quartus Pro pitfalls in MiSTer's code

MiSTer builds with Quartus Standard. Quartus Pro is stricter or behaves differently:

| Pitfall | Effect | Fix |
|---|---|---|
| `reg x = 0;` **inside** an `always` block (warning 16754) | Pro resets the register on every pass. Consequences here: the video command only arrived in `WIDTH` (no HDMI signal), OSD not scaled up | remove the initial value (static, as under Quartus Standard) — `sys_top_de25.v`, `pro/osd.v`, `pro/audio_out.sv`, `pro/hps_io.sv` |
| output port without `reg` but assigned in `always` | error 13386 | `output reg` — `pro/ddr_svc.sv` |
| boolean VHDL generics as `"false"`/`"true"` | Pro reads the string as a number (error 13832) | `1'b0`/`1'b1` — ascal in `sys_top_de25.v` |
| signals in a `generate` block but used outside it | error | at module level — `pro/hps_io.sv` |
| `inout` port (`SDRAM_DQ`) assigned in `always` | error 13386 | `inout wire` with tri-state `assign DQ = oe ? out : 'z` — `cores/menu/pro/sdram.sv` |
| `altddio_out` (Cyclone V primitive) | error 287078 | for the SDRAM clock: PLL output with phase shift via `ip/sdram_clk_ddio` (see SDRAM above) — `cores/memtest/pro/memtest.sv`; the menu core still uses `~clk` (it only clears the SDRAM) |
| data register with clock enable on an `inout` with I/O registers | error 14996/24403 | load the data register on every cycle (see SDRAM above) |
| module name `pll` in the core | collides with the PLL in the HPS system | rename (`pll_menu`) — `cores/menu/pro/menu.sv` |
| identifiers used before their declaration (warnings 16746/16749) | Quartus creates an implicit net; a later declaration `wire x = expression;` is treated as an "initial value" and discarded — net without driver (warning **16788**). On the C64: drive did not respond | `wire x;` before the first use, assignment as `assign` — `cores/c64`, `sys_top_de25.v` (pal_d/pal_a). Check for 16788 after every build |
| `static reg x = 0;` in the `always` block | warning 16754 disappears, but the register is still reset on every cycle | do not use — move the register to module level |
| memory with two port widths, written by both ports | Agilex 5 cannot do this (altera_syncram: error 272006, no second clock either) — Quartus builds registers | own modules with equal width (`cores/c64/rtl/`) |
| dual-port RAM following Intel's template | "uninferred due to unsupported read-during-write behavior" (info 276009) — registers instead of M20K | `(* ramstyle = "no_rw_check" *)` |
| `ram_init_file = " "` (space as "no file") | Quartus Pro crashes (assertion `required_unc_path_size`) | load contents via `$readmemh` only if a file is given |
| VHDL `case` without `others`, direct instance without `entity` | error 13630 / 13780 | `when others`, `entity work.x` |

**Rule for every new MiSTer file and every core:** after the first build, search
`*.syn.rpt` for `Warning (16754)` — target 0. And after every build check the
`HPS IO hash` in the output of `quartus_pfg`: `474D6C20…`.

## Bursts across 4 KB boundaries (P4, 2026-10-18)

The C64 (drive) reads DDRAM in bursts starting at arbitrary addresses. A burst
across a 4 KB boundary violates AXI; over F2SDRAM the part beyond
the boundary arrived corrupted (on the board: exactly the disk sectors spanning a
4 KB boundary read incorrectly). Platform Designer does not split such bursts
itself, and the Avalon bridges have no setting for it. Therefore
`sysmem_de25` has an `avl_burst_4k` behind each `f2s_halt_de25`:
read commands across a boundary become two commands, write bursts
start a new burst at the boundary; without a boundary everything passes through unchanged
and without an extra cycle (testbench `tb/tb_avl_burst_4k.v`).

## Reads always with all bytes (P5, 2026-10-22)

MiSTer cores often set `DDRAM_BE` only on writes; on reads the
value of the last write remains (z486 `main_memory`). The DE10-Nano
ignores byteenable on reads. Platform Designer, however, turns this into a
narrow AXI read: over F2SDRAM **only the enabled bytes** came
back, the rest was 0 (on the board with the z486 mailbox: written
`44434241`, read `00004200`). `sysmem_de25` therefore always forwards `byteenable = FF`
for ram1/ram2 on reads (`tb/tb_sysmem_de25.v` checks this).
Partial writes (wstrb), on the other hand, work correctly.

What proved useful for debugging (not in the repo): Verilator simulation of the
core with a DDR protocol log; a temporary recorder in `sysmem` that
captures the core and F2SDRAM sides and writes the log via the free port
ram2 into DDR (read out with Python via `/dev/mem`). Over JTAG, no SLD
nodes are visible in HPS-first mode (`jtagconfig -n` empty), so
neither Signal Tap nor the In-System Memory Content Editor. The CCU's system cache
(DMI-SMC) was innocent.

## Screenshot in framebuffer mode (P5, 2026-10-22)

Main's screenshot reads the scaler's buffer. When a core shows its
framebuffer (`MISTER_FB`, e.g. z486 in SVGA modes), that buffer only contains the
core's VGA input. Main therefore reads the picture directly from DDR
(patch 0010). Only the scaler knows the palette at 8 bpp; `sys_top_de25`
therefore keeps a **shadow copy** (256 × 24 bit, 1 M20K, written with
the core's `FB_PAL_*` signals) and returns it via the new
UIO command **`0x4E`** (unused by MiSTer): first response `0x8000 |`
number of palette writes (diagnostics), then two words per entry
(G/B, then R).

## Slim HPS system (P5, 2026-10-18)

Terasic's GHRD comes with demo and debug parts that MiSTer does not need and
that took up a lot of FPGA space (menu core: 22,010 ALMs, 190 M20K, of which the
menu itself only ~800 ALMs). For the z486 (PC alone ~25,700 ALMs, 209 M20K),
`hps_slim.tcl` removes them:

| Part | Purpose in the GHRD | Usage |
|---|---|---|
| `ocm` | 256 KB on-chip RAM on `hps2fpga` | 128 M20K |
| `subsys_debug` | three JTAG masters (System Console) | ~1,200 ALMs |
| ACE5-Lite translator + bus | only for the JTAG master to the HPS memory | ~2,600 ALMs |
| `ext_hps_f2sdram_master` | window of the JTAG master to the F2SDRAM | – |
| FPGA→HPS bridge (`f2s_data_width 0` in the HPS IP) | without a counterpart, Quartus demands a connection (24265/129015); tying the inputs to constants is not enough | – |

Result for the menu core: **13,735 ALMs, 59 M20K** (−8,275 / −131), HPS IO hash
unchanged (`474D6C20…`, also with the FPGA→HPS bridge disabled); on the board,
switching menu ↔ C64 without issues. What remains: LW bridge with
`subsys_periph`, F2SDRAM with the three DDR ports, `hps2fpga` (unused, may
stay open). Without the JTAG masters, tests via System Console no longer work —
Signal Tap still does; for a debug variant, run `fetch_hps.py` without
`hps_slim.tcl`.

**Pitfall:** Quartus Pro does not regenerate `qsys_top` during the core build when
the `.qsys` has changed — the build then uses the old `qsys_top/synth/
qsys_top.v` (error "undefined entity ocm"). `fetch_hps.py` therefore calls
`qsys-generate` at the end (with `--search-path=custom_ip/**/*,$`, otherwise
`f2sdram_adapter` is missing).

## Verification

- Testbenches: `tb/tb_hps_gp_bridge.v`, `tb/tb_hdmi_config.v`,
  `tb/tb_sysmem_de25.v`, `tb/tb_video_debug.v`, `tb/tb_testpattern.v`,
  `tb/tb_pll_cfg_de25.v` (with model `tb/hvio_pll_model.v`),
  `tb/tb_i2c_master_de25.v` (model `tb/i2c_smbus_model.v`),
  `tb/tb_avl_slow_cdc.v`, `tb/tb_f2s_halt_de25.v` (`python tb/run_sim.py`).
- `sys_top_de25` as a whole only in Quartus: MiSTer's sources use
  identifiers before their declaration — Quartus accepts this, Questa does not.
- On the board: `linux/tools/gp_check.py` reads the ID over the bridge;
  `p3/linux/pll_cfg.py` (read PLL registers, reconfigure: `mhz 108`),
  `p3/linux/i2c_test.py` (read the ADV7513 ID; stop Main first),
  `p3/linux/f2s_halt.py` (read, set, clear the DDR lock).
- Python tools access `/dev/mem` via `ctypes` with true 32-bit accesses:
  `struct.pack_into` on the mmap was split into partial accesses, and the
  I2C master then only saw the lowest byte of the command.
