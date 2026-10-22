# P0 — Switching cores from Linux (feasibility)

Goal: show that Linux can load the DE25-Nano's FPGA with different cores at
runtime, before any work goes into the MiSTer port
(see [docs/roadmap.md](../docs/roadmap.md)).

Analogy: So far (C64) the FPGA is like a permanently installed circuit board —
the flash contains everything, and it starts before Linux. For MiSTer
operation it becomes a slot: the flash only contains the "frame" (I/O ring +
HPS bootloader, **HPS-first**), and the "plug-in card" (core, `.core.rbf`) is
inserted first by U-Boot and later by Linux — and can be swapped for another
one at any time.

## What gets built

A Quartus project `quartus/p0.qpf` with three revisions. All of them have the
same pins and the same HPS system (from the C64 project, with the bridges
`c64_m0`/`disk_m0`):

| Revision | LEDR[3:0] | LEDR[7] | Special feature | ID |
|---|---|---|---|---|
| `p0_a` | running light | heartbeat from CLOCK0_50 | — | `R25A` |
| `p0_b` | blink together at 2 Hz | heartbeat from CLOCK0_50 | only different logic | `R25B` |
| `p0_c` | binary counter | heartbeat from PLL | own PLL `pll_c64` | `R25C` |

Registers for Linux (`rtl/p0_regs.v`, testbench `tb/tb_p0_regs.v`), LW bridge
base `0x2000_0000`:

| Address | Register |
|---|---|
| `0x2001_0100` | ID (`R25A`/`B`/`C`) |
| `0x2001_0104` | SCRATCH (read/write) |
| `0x2001_0108` | UPTIME (100 MHz clock cycles since reset → small = freshly loaded) |
| `0x2001_010C` | STATUS: bits 3..0 SW, bits 5..4 KEY (1 = pressed) |
| `0x2001_4000` | same register set, ID `R25-` |

## Questions P0 answers

1. Can a core be loaded repeatedly and alternately (≥ 20 times)?
2. Does an own PLL (revision C) change the checksums `IO hash` / `HPS IO hash`?
   If so, a core must not bring its own PLL.
3. Does the LW bridge remain usable after loading?
4. Is `/dev/mem` allowed, and where is the DDR (`/proc/iomem`)?
5. Does Terasic's U-Boot know `fpga load`?
6. Does `sudo reboot` work? In FPGA-first operation (C64) Linux shuts down
   cleanly, but the hardware restart hangs (observed 2026-10-15, last
   message "systemd-shutdown: Sending SIGTERM", watchdog at 10 min).
   Main_MiSTer restarts on some actions — check this in HPS-first operation.
7. Does USB (WLAN stick, keyboard, gamepads) survive the reload? (Only
   noticed during the attempt.)

## Procedure

### Step 1 — Pre-check on the board (possible today, changes nothing)

With the current C64 setup. Copy the files to the board (adjust the board IP;
Windows ships with `scp`):

```
scp p0\linux\* terasic@<board-ip>:~/p0/
```

On the board:

```
sudo systemctl stop c64d
sudo systemctl disable c64d          # until P0 is done
sudo apt install device-tree-compiler u-boot-tools
cd ~/p0
sudo bash p0_check.sh | tee p0_check.txt
```

Please return `p0_check.txt` in full. If the modules show "FEHLT" (missing)
or U-Boot lacks `fpga load`, step 3 only continues after this is resolved.

### Step 2 — Build (PC)

```
subst Q: <path to Retro25>
python tools\fetch_hps.py          (once; back then from C64-DE25 — today: specify Terasic's GHRD as the source, see README.md)
Q:\p0\quartus\build_p0.bat
```

`build_p0.bat` builds all three revisions and calls `quartus_pfg` with
`-o hps=1`. Result in `p0\quartus\output_files\`: `p0_a.hps.jic`
(for the flash) and `p0_a/b/c.core.rbf`. At the end it shows the checksums —
so **question 2 is already answered** before the board comes into play.
Please return the lines containing "hash".

If Quartus complains about ungenerated IP: open the project once in the GUI
(`Q:\p0\quartus\p0.qpf`), Platform Designer `qsys_top.qsys` → *Generate HDL*.

### Step 3 — Extend the boot script (board)

```
scp p0\quartus\output_files\p0_*.core.rbf terasic@<board-ip>:~/p0/
```

On the board:

```
cd ~/p0
sudo bash p0_bootscr.sh install p0_a.core.rbf
sudo poweroff
```

The script backs up the original as `boot.scr.uimg.orig` and makes U-Boot
load the core `retro25/core.rbf` before `bridge enable`.

### Step 4 — HPS-first into the flash (PC)

Set SW5 to AS mode (SW5.1 OFF, SW5.2 and SW5.3 ON, only while powered off),
power the board on, then run `Q:\p0\quartus\flash_p0.bat`. Afterwards power
cycle.

Expected: the HPS UART (COM11, 115200) shows
`Retro25: lade retro25/core.rbf ins FPGA` ("loading retro25/core.rbf into the
FPGA"), LEDR[3:0] show the running light, LEDR[7] blinks, Linux boots as
usual.

### Step 5 — Switch cores (board)

```
cd ~/p0
sudo python3 p0_switch.py --read
sudo python3 p0_switch.py p0_b.core.rbf
sudo python3 p0_switch.py p0_c.core.rbf
sudo python3 p0_switch.py --loop 20 p0_a.core.rbf p0_b.core.rbf p0_c.core.rbf
```

Expected: the LEDs change pattern, the ID matches the core, scratch "ok",
uptime only fractions of a second each time. Please return the output and,
if needed, `dmesg | tail -30`.

## Back to the C64

```
sudo bash ~/p0/p0_bootscr.sh restore
sudo systemctl enable --now c64d
```

Then `C64-DE25\quartus_hps\flash_program.bat` (SW5 in AS mode), power
cycle.

**Emergency** (Linux no longer boots): put the SD card into the PC and copy
`boot.scr.uimg.orig` to `boot.scr.uimg` on the FAT partition. The flash can
always be rewritten via JTAG (`flash_program.bat`), if necessary with
Terasic's `golden_top_hps.jic`.

## Results

| Question | Result |
|---|---|
| 1 Repeated loading | **Yes.** 2026-10-15 via the serial console: 21 loads (A↔B, `--loop 10`), 0 errors, **2.13 s** each; bridges active during this (`bridge enable` from U-Boot), kernel unaffected. The first attempt via SSH seemed to hang — in fact only the USB WLAN had dropped out (see question 7). The message "memory leak will occur if overlay removed" is harmless (also in Altera's example) |
| 2 PLL in the I/O ring | **An own PLL in the core is allowed.** Built: A and B have the same `IO hash` (`A36E45D7…`), C with its own PLL `pll_c64` has a different `IO hash` (`849E8EB8…`); `HPS IO hash` identical for all (`474D6C20…`). On the board C still loads: ID `R25C`, PLL runs at the correct frequency (LED 3: 29.67 s for 7 cycles = 4.24 s, nominal 4.26 s), A↔C 10× without errors. Explanation (hypothesis, consistent with all observations): in HPS-first operation only the HPS I/O and HPS memory belong to the flash part; FPGA I/O and PLLs come fresh with every `core.rbf`. The `HPS IO hash` is what is binding. Not tested: differing pin assignments |
| 3 LW bridge after loading | **Yes.** After every load the ID is correct, SCRATCH writable/readable, `disk_m0` responds, UPTIME 0.05 s (core freshly started) |
| 4 `/dev/mem`, DDR location | `/dev/mem` works (sysid `0xacd5cafe` read). HPS DDR: 1 GB from `0x8000_0000`; `0x8000_0000–0x81FF_FFFF` reserved (svc buffer), System RAM `0x8200_0000–0xBFFF_FFFF`. With MiSTer's 512 MB window, Linux would keep 512 MB |
| 5 U-Boot `fpga load` | **Yes.** First HPS-first boot 2026-10-15: Terasic's SPL runs unchanged, `1699840 bytes read in 89 ms … FPGA reconfiguration OK!`, then `bridge enable` and Linux as usual; running light (core A) visible |
| 6 `reboot` | **Yes in HPS-first operation** (2026-10-15: `sudo reboot` restarts, U-Boot loads the core again). In FPGA-first operation (C64) it hangs after shutdown |
| 7 USB during loading | **Only the WLAN stick.** On every load from Linux the RT5370 stick (`rt2x00usb`) gets USB timeouts (`error -110`) during configuration and loses the connection permanently (reloading the driver, USB reset, re-plugging did not help; only a power cycle). Keyboard and gamepads: no disconnect/reconnect across all switches. USB stick: 200 MB before/after the switch 11.4/11.2 MB/s, no errors. → USB controller is fine; use wired Ethernet for networking (onboard `eth0` or RTL8153 adapter). Reviving fails: reconnecting and restarting wpa_supplicant/NetworkManager do not help; `modprobe -r rt2800usb` in the error state **crashes the kernel** (timer of the unloaded module, `__run_timers`). Only a reboot helps. **Solution: switch the radio off preventively** (`p0_wlan.sh switch`: `nmcli radio wifi off` → load core → `on`): tested 2×, no `error -110`, back online after 3–4 s. For Main_MiSTer: radio off/on before/after every core load (e.g. `rfkill block/unblock wifi`) |

Pre-check 2026-10-15: modules `stratix10-soc`, `of-fpga-region`, `fpga-region`,
`fpga-bridge` present and loaded; `/sys/class/fpga_manager/fpga0`
("Stratix10 SOC FPGA Manager", state `unknown`), `region0`, configfs overlays
present; no `fpga_bridge` entries (bridges are not disabled during loading).
The boot script contains `bridge enable` → `p0_bootscr.sh` fits.

Done along the way: enlarged the SD card's root partition (Terasic image:
3.4 GB, full) to the whole 29 GB card (`sfdisk -N 2`, start 616449 kept,
`resize2fs`). Backup of the old table: `~/mmcblk0-partitionen.txt`.
