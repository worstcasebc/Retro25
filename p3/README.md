# P3 — F2SDRAM, scaler, menu core

Goal: core selection via F12 as on MiSTer. Plan and decisions
(2026-10-15) in `docs/roadmap.md`:

- **Connection:** export three Avalon ports (vbuf 128 bit, ram1/ram2 64 bit)
  in `qsys_top`; Platform Designer generates the arbiter, width adaptation,
  clock crossing and the path to the AXI4 F2SDRAM (256 bit, 100 MHz).
  The hard HPS IP remains unchanged.
- **DDR window:** upper 512 MB `0xA000_0000–0xBFFF_FFFF`; FPGA address
  `0x2000_0000` (MiSTer) + bit 31. Reservation via `fdt` in the U-Boot script.
- **Order:** 1 check the address model · 2 ports + memory test ·
  3 ascal with fixed 720p PLL · 4 HDMI PLL reconfiguration + ADV7513 via
  Main · 5 menu core.

## Step 1 — Address model and coherency (without new RTL)

The GHRD already has a JTAG master on F2SDRAM (`hps_f2sdram` →
`ext_hps_f2sdram_master`, 4 GB window from 0 → `f2sdram_adapter`, AxCACHE=2).
It is present in every core with `qsys_top`, so also in the test core.

Because the future window still belongs to Linux today, we test on dedicated,
pinned pages of a Linux process:

1. Board: `sudo python3 ~/p3/f2sdram_probe.py` — shows physical addresses,
   the expected values and the System Console commands, then waits.
2. PC: Quartus → Tools → System Debugging Tools → **System Console**:
   ```
   source Q:/p3/sc/f2sdram.tcl
   f2s_scan  0x…  3       ;# read with all three masters: which is which?
   f2s_open  <number>
   f2s_read  0x…  2       ;# addresses from step 1
   f2s_write 0x…  0xCAFE0001
   ```
3. Board: Enter — the script reports whether the written value is visible
   immediately or only after eviction from the cache.
4. Strict: `sudo python3 f2sdram_probe.py --spin` reads without pausing while
   System Console writes (stop Main first, it shares the CPU core).

| Question | Result (2026-10-15) |
|---|---|
| Does the FPGA see physical addresses? | **Yes.** Both 4 GB JTAG masters (`phy_1`, `phy_2` = `hps_m` via F2H and `hps_f2sdram`) read the pattern at the physical address from `/proc/self/pagemap`, without offset. `phy_0` (`fpga_m`) returns 0. For P3: FPGA address = physical address, `0xA000_0000` maps directly to `0xA000_0000`. |
| Do FPGA writes reach the CPU without cache maintenance? | **Yes, via both paths.** Strict test (`--spin`): one CPU core (CPU 3, Main stopped) reads two locations continuously, so the lines stay in L1. It still saw the JTAG writes from `phy_1` and `phy_2` immediately. The hardware keeps the caches coherent, also on the F2SDRAM path with AxCACHE=2. Which `phy_N` is F2SDRAM remains open (unnamed without a linked design); irrelevant given identical behavior. |

System Console also works without the GUI (this is how the strict test ran):
`(sleep 60 | system-console.exe --cli --script=… )`. stdin must stay open,
otherwise the console exits prematurely. Right after startup the search for
JTAG masters is still incomplete, so wait until all three are there.

## Step 2a — Reserve the DDR window (done 2026-10-15)

`linux/boot/retro25-bootscr.sh install <start.core.rbf>` (successor of
`p0/linux/p0_bootscr.sh`) extends Terasic's U-Boot script: load the start
core and, after loading the device tree, create a node
`/reserved-memory/retro25_fpga@a0000000` (512 MB, `no-map`) via `fdt`.

- Pitfall: otherwise `booti` relocates the device tree to the end of RAM
  (`0xBEAD2000`, right inside the window), and the kernel then reports
  "failed to reserve memory" → `setenv fdt_high 0xffffffffffffffff` keeps it
  at the load address `0x86000000`.
- Result: the kernel reports `0xa0000000..0xbfffffff nomap non-reusable
  retro25_fpga@a0000000`; System RAM now only `0x8200_0000–0x9FFF_FFFF`,
  `free`: 424 MB (previously 934); CMA moves to `0x9CC0_0000`.
  `/dev/mem` allows reading/writing in the window (checked at `0xA000_0000`,
  `0xB000_0000`, `0xBFFF_F000`). Main runs unchanged.

## Step 2b/2c — DDR ports and memory test (done 2026-10-15)

- **Platform Designer:** `sys/de25/hps_f2sdram_ports.tcl` creates three
  Avalon-MM Clock Crossing Bridges in `qsys_top` (`f2s_vbuf` 128 bit,
  `f2s_ram1`/`f2s_ram2` 64 bit; 32-bit byte addresses, bursts up to 128,
  FIFOs 256). Each one gets a Clock Bridge in front with an exported
  input — a directly exported clock input does not count as a clock source,
  and then the reset synchronizer has no clock (error in `qsys-generate`).
  `tools/fetch_hps.py` applies the script automatically when fetching into
  `sys/hps` (throwaway project in the temp folder, because qsys-script adds
  IP files to the specified project). Avoid applying it multiple times to
  already modified files (instances are then named `…_0`).
- **RTL:** `sysmem_de25` passes the ports through and maps every address into
  the window (`{3'b101, Byte[28:0]}`); `sys_top_de25` connects to
  `qsys_top`, vbuf is tied to 0 in direct video mode.
  Testbenches `tb_sysmem_de25`, `tb_ddr_test`.
- **Test core:** after reset (and via OSD) `ddr_test` writes 128 KB
  from MiSTer address `0x3000_0000`, reads it back, and shows the result as a
  field on the left edge. Cross-check: `sudo python3 p3/linux/ddr_check.py`.
- **Build:** HPS IO hash unchanged (`474D6C20…`), timing met
  (setup ≥ 3.3 ns), 13,058 ALMs (+2,540 for bridges and interconnect),
  138 RAM blocks (+5).
- **Board:** field green (FPGA reads back its pattern without errors); Linux
  reads 16,384 words at `0xB000_0000` without errors, also after a restart via
  OSD with a new seed — the FPGA→DDR→Linux path works.

## Step 3 — ascal with fixed 720p PLL (done 2026-10-15)

- Scaler active (`MISTER_DEBUG_NOHDMI` off), triple buffer in the DDR window,
  fixed HDMI PLL. The main bug was the Quartus Pro pitfall 16754 (local
  `reg x = 0;` in `always` blocks are reset on every pass), details in
  `sys/de25/README.md`.
- Tool: `p3/linux/video_debug.py` reads the measurement points of the video
  chain (`sys/de25/video_debug.v`, `0x2001_4000`).

## Step 4 — HDMI PLL at runtime, ADV7513 via Main (done 2026-10-16)

- **Decided (2026-10-15):** the FPGA translates Main's PLL registers
  (Cyclone V format) into the Agilex sequence (`sys/de25/pll_cfg_de25.v`);
  Main computes integer values only (`linux/main/patches/0004-…`). Own I2C
  master in the FPGA (`sys/de25/i2c_master_de25.v`), Main gets a replacement
  `smbus.cpp` (`linux/main/de25/`). Linux reaches both via `disk_m0`
  (`0x2001_5000` PLL debug, `0x2001_6000` I2C; `avl_slow_cdc` for the
  clock crossing).
- **Board:** Main switches the PLL for `video_mode` 0/1/6/8 (74.25 / 65 /
  25.175 / 148.5 MHz, measured with `video_debug.py`), lock after ~1 ms, no
  timeouts. Main opens the ADV7513 (0x39, EDID 0x3F, SPD 0x38) and reads
  the EDID. 1080p with picture and OSD confirmed by the user.
- **Pitfalls:** only HVIO IOPLLs have the reconfiguration port, and the
  reference clock determines the type (CLOCK1_50 is HVIO, CLOCK0_50 HSIO);
  `pll_audio` must not go into the IO96B bank of the HPS memory (HPS IO hash).
  Python accesses to `/dev/mem` use `ctypes` (true 32-bit accesses).
- Tools: `p3/linux/pll_cfg.py` (read/switch the PLL),
  `p3/linux/i2c_test.py` (read the ADV7513, stop Main first).
- **Open:** `vsync_adjust=2` (low latency, needs a fractional PLL),
  `direct_video`.

## Step 5 — Menu core, core selection via F12 (done 2026-10-16)

- **Decided (2026-10-16):** adopt MiSTer's Menu_MiSTer
  (`tools/fetch_menu.py`, commit `fa83dc1`, `cores/menu/vendor/`); as on
  MiSTer, cores live in folders under `/media/fat` (`_Retro25/`), the
  menu core as `/media/fat/menu.rbf` (`install.sh` puts it there).
- Adaptations for Quartus Pro in `cores/menu/pro/` (diff per `*.patch`):
  `pll` → `pll_menu` (the name `pll` is taken in the HPS system), initial
  values moved out of `always` blocks (pitfall 16754), `SDRAM_DQ` as
  `inout wire` with tri-state, `altddio_out` replaced by
  `assign SDRAM_CLK = ~clk`.
- **Board:** menu as start core (noise background, OSD with core list),
  loading the test pattern via F12 and back to the menu — confirmed by the
  user; 20 switches menu ↔ test pattern via Main without errors.
- **Debugging the core switch** (Linux hung: `arm-smmu-v3 … CMD_SYNC timeout`):
  1. The FPGA must never be reloaded in the middle of an F2SDRAM access —
     the HPS side then waits forever for the rest of the burst or for the
     read data to be accepted, the SMMU hangs and with it all of Linux. New:
     `sys/de25/f2s_halt_de25.v` in front of every DDR port (counterpart of
     MiSTer's `f2sdram_safe_terminator`); before loading, Main halts all
     ports and waits for "empty" (register `0x2001_7000`, tool
     `p3/linux/f2s_halt.py`).
  2. The actual trigger, however, was `cores/testpattern/ddr_test.v`: a
     reset **inside** the core (Main sets `status[0]` several times at
     startup) aborted a write burst. The lock in sys does not see that.
     Now `ddr_test` finishes a started burst even during reset. **Rule for
     every core:** never abort a DDRAM burst by reset.
  3. "Board dead" was twice just the network: the USB WLAN stick drops out
     during reloading (known from P0). The board is now on Ethernet.
- **Side effect:** the many hard resets damaged the root file system of the
  SD card (superblock, 16 programs in `/usr/bin`). Rescued with
  `tools/sd_rescue.py` (image under Windows) and `e2fsck`/`debugfs` in
  Docker; this led to step P3a (read-only root) in `docs/roadmap.md`.
- **Open:** `vsync_adjust=2`, `direct_video`, `shmem_map(0x1FF00000)`
  outside the window; the menu's SDRAM only does size detection, clock
  directly inverted instead of DDIO.
