# z486 — 486 PC (P5)

nand2mario's [z486_MiSTer](https://github.com/nand2mario/z486_MiSTer) — a
486 PC (roughly a 486DX2-66) — in the Retro25 framework.

**License:** z486_MiSTer has no license file; the CPU (`src/z486`) is under
Apache-2.0 only for `*.sv`, `*.svh`, `*.py`, `*.md`, and the microcode
(`ucode.hex`) is explicitly excluded. That is why **none** of it is in the
repository — not even the adapted copies (`pro/`). `tools/fetch_z486.py`
fetches the third-party code from a fixed commit into `vendor/`, `make_pro.py`
generates `pro/` by text substitution (the search patterns in it are short
excerpts). Built bitstreams contain the microcode: **do not
redistribute**, build them yourself.

## Status (2026-10-22)

| Area | Status |
|---|---|
| CPU, BIOS, VGA (ET4000, 2 MB) | ✔ FreeDOS, Windows 95 OSR2 |
| Hard disk (IDE, `.vhd`), floppy, CD-ROM (ISO) | ✔ read and write |
| Keyboard, mouse, joystick | ✔ |
| Sound Blaster, OPL3 | ✔ (Doom 37 fps, Quake with sound) |
| SVGA framebuffer | ✔ up to 1024×768×8, 800×600×16, 640×480×24 |
| x87 FPU | ✔ Quake `timedemo demo1` 8.3 fps |
| Shared folder (MISTERFS) | ✔ under DOS |
| Screenshot (Main) | ✔ in SVGA mode too |
| Known issues | occasional 20–30 s pause during the Windows startup jingle |

Utilization: 43,159 ALMs (92%), 282 M20K, timing met at 85 MHz,
HPS IO hash identical.

## Building

```
python tools/setup.py                    # once: fetches third-party code, ROMs, generates pro/
python cores/z486/make_pro.py            # after changes to make_pro.py: pro/, core.tcl, probe/
python tools/make_core_qsf.py z486
Q:\tools\build_core.bat z486             # ~20 min; result quartus/output_files/z486.core.rbf
```

On the board: `z486.core.rbf` as `/media/fat/_Retro25/Z486.rbf`; `boot0.rom`
and `boot1.rom` (from `roms/z486/`, `tools/fetch_z486.py --roms`) into
`/media/fat/games/Z486/` (or onto the USB stick, see "USB stick") — Main loads
them into the core via the DDR every time the core starts. Restarting Main
does **not** load a new core: `echo 'load_core /media/fat/_Retro25/Z486.rbf'
> /dev/MiSTer_cmd` or via the menu. Shut down Windows first (a
DOS prompt with no program running is fine), otherwise Windows checks the
disk on the next start.

## Usage (Z5, 2026-10-18)

- **OSD: Win + F12** or the Menu key — F12 alone does not work with PC cores
  (Main `is_f12_mod_needed()`: DOS/Windows programs need F12).
- Hard disk: OSD → **IDE 0-0** → `.vhd` (raw image) → **Reset and apply
  HDD**. It is only remembered after **Save settings** (`config/Z486sys.cfg`);
  from then on Main mounts it on every start.
- An MGL does not help with x86: it mounts the disk only after the core has
  started, when the BIOS has already probed IDE, and it saves
  nothing.
- Test disk: `tools/fetch_z486.py --roms` → `roms/z486/freedos.vhd`
  (upstream `verilator/freedos.zip`, FreeDOS 1.3, 32 MB FAT16) into
  `/media/fat/games/Z486/`. Boots to `C:\>` (keyboard works).

## Games (Z6, 2026-10-18)

Data disk on IDE 0-1 (`D:` under FreeDOS), created with
`tools/make_dos_disk.py` (Docker: mkfs.fat + mtools), e.g.
`python tools/make_dos_disk.py roms/z486/games.vhd --size 256 <folder>=DOOMINST`.

Doom 1.9 shareware (`doom19s.zip` from idgames, installer run
under DOS): runs smoothly, Sound Blaster (220/IRQ 5/DMA 1) with music and
effects over HDMI. `doom -timedemo demo3`: 2134 gametics in 2018 realtics
= **37.0 fps** (shareware default settings; upstream reports 29.1 fps
at full detail on the DE10-Nano).

## Mouse and joystick (2026-10-19)

- **Mouse** (USB, via Main as a PS/2 mouse): works with Main patch 0007 — the
  Terasic kernel has no `mousedev`; before that only the buttons got through.
  FreeDOS loads `CTMOUSE` in `FDAUTO.BAT`; test `C:\FREEDOS\BIN\CTMOUSE\MOUSETST`.
  Doom: `use_mouse 1` in `DEFAULT.CFG` (SETUP: Keyboard + Mouse) — the
  shareware default was 0.
- **Joystick** (game port 201h, USB pads via Main): Main only sends the
  buttons once the pad has been mapped **in the z486** — OSD (Win + F12) →
  system page → **Define joystick buttons** (one file
  `config/inputs/Z486_input_<vid>_<pid>_v3.map` applies to all identical pads;
  map it in Main in the menu core first, see `cores/c64/README.md`). Checking
  without a game: `debug`, `i 201` → `F0` without, `E0` with button 1 (buttons active
  low, bits 4–7). Doom: SETUP → Keyboard + Joystick, calibrate — works.
  Besides the keyboard, Doom supports only mouse *or* joystick.

## Floppy and CD-ROM (Z7, 2026-10-19)

Test images: `tools/make_dos_disk.py … --type floppy` (1.44 MB FAT12) or
`--type iso` (ISO 9660 + Joliet), each with `TEST\DATA.BIN` (512 KB).

- **CD-ROM** (OSD **IDE 1-0**, `.iso`): works. FreeDOS loads UDVD2 ("No V2.0C+
  PCI!", finds `IDE0 Secondary-master` via the ISA ports) + SHSUCDX → `E:`.
  `fc /b A:\TEST\DATA.BIN E:\TEST\DATA.BIN`: no differences.
- **Floppy read** (OSD **Floppy A:**): works.
- **Floppy write** (2026-10-20): works after fixing upstream
  [#125](https://github.com/nand2mario/z486_MiSTer/issues/125).
  Cause: `sdram.v` gave port 0 (CPU) fixed priority over port 1 (DMA).
  While writing, the BIOS polls for the interrupt, and the CPU occupies the
  memory in ~83% of the cycles. The DMA got hardly any bytes for the floppy
  controller (measured ~150 B per 250 ms, counter in the core + Main debug patch).
  After ~2 s the BIOS aborts and DOS hangs. Reading (device → memory) and
  sound DMA were not affected; the Verilator simulation did not show it.
  Fix (`make_pro.py`): DMA before CPU, as in a PC (HOLD/HLDA). The DMA has
  at most one request outstanding and cannot starve the CPU.
  Test: `copy C:\FREEDOS\BIN\FC.EXE A:\Z.EXE` takes 0.2 s for 28 sectors
  (previously a hang), the file on `test.img` is byte-identical.
- With a floppy inserted, the BIOS boots from A: (`Boot 1st:
  Floppy/Hard Disk`) → OSD **Hardware → Boot 1st: Hard Disk**.

## USB stick and Windows 95 (2026-10-20)

- **Images from the stick:** Main looks for the core folder on the sticks first
  (`/media/usbN/games/Z486`), then on the SD card, and only takes the
  first match. If `games/Z486` exists on the stick, the OSD shows only
  its files — and Main also loads **`boot0.rom`/`boot1.rom`** from there.
  If they are missing, the screen stays black (no BIOS) → copy the ROMs to the
  stick as well.
- The **IDE 0-x** slots accept only `.vhd` (raw image; simply rename an `.img`),
  **IDE 1-x** (CD) `.vhd/.iso/.cue/.chd`, floppy `.img/.ima/.vfd`.
  Main rejects a disk image on IDE 1-x ("Cannot hot-mount HDD image
  to CD!").
- **Windows 95 OSR2** (English, ISO on IDE 1-0, empty 512 MB `.vhd` on
  IDE 0-0, Boot 1st: CD-ROM, Hard Disk after the first reboot) installs
  and starts up to the desktop; file system and paging run in 32-bit mode
  (no MS-DOS compatibility mode). A Japanese Win95 image, on the other hand,
  stopped after loading `DISPLAY.DRV` (not pursued further).
- **Write speed:** Main opened images with `O_SYNC` — every IDE write command
  (often 1 sector under Windows) waited for the storage medium; both stick and
  SD card managed only ~150 operations/s that way (~40 KB/s, the installation
  took hours). Main patch 0008 buffers in Linux and calls `fsync` after
  1 s without writes: `xcopy` under Win95 now writes ~300–400 KB/s.
  Only cut power or pull the stick once nothing has been written for ~1 s.
- US keyboard layout in Windows: `:` is on Shift + Ö (otherwise you get `;`).

## Shared folder (Z7, 2026-10-22)

File exchange with the PC without a disk image: the folder `games/Z486/shared`
(on the stick or the SD card, depending on where `games/Z486` is) appears
as a network drive under DOS.

- Driver: `misterfs.exe` from ao486_MiSTer (MIT license;
  `tools/fetch_z486.py --roms` fetches it into `roms/z486/`). Invoke it with the
  drive letter **without** a slash: `MISTERFS E`. Most convenient: copy it to
  `C:\` and add it to `AUTOEXEC.BAT`. With EMM386, exclude the
  region: `X=CE00-CFFF`.
- Tested under Win95 DOS (Command prompt only): `dir`, `type`, `copy` in
  both directions, `fc /b` byte-identical. Not yet tested under the Windows
  GUI.
- **How it works:** The driver (a DOS redirector, INT 2Fh) places each
  file request into an 8 KB mailbox at PC address `CE000`. Main
  (`x86_share.cpp`) polls it in the DDR at `0x300CE000`, executes the request on
  real files and puts the response back. On the ao486 the entire
  PC memory is in the DDR; on the z486 it is in the SDRAM. Therefore the core routes
  `CE000–CFFFF` as a **device page** (uncached, direct) into the DDR via the same
  path as the linear SVGA framebuffer (`main_memory`, states
  `FB_WRITE`/`FB_READ`). Testbench `tb/tb_main_memory_share.v`.
- Main: patch 0009 (copy the mailbox aligned, otherwise SIGBUS) and
  `shmem_map` for addresses in the middle of a page (`linux/main/de25/shmem.cpp`).
- **Pitfall (sys):** The z486 leaves `DDRAM_BE` at the value of the last write
  access during reads. Over F2SDRAM only those bytes then came
  back, the rest was 0 — `sysmem_de25` now always reads with `FF`
  (`sys/de25/README.md`). Partial writes work.
- Stress test `SHTEST.COM` (50,000 random byte/word/dword accesses to
  `CE00:0100–1FFF` against a copy in RAM): no errors.
- At startup the BIOS tests `CE0A0`/`CF0A0` as RAM and scans `CF000–CFE00`
  for option ROMs — now in the DDR, as on the ao486; harmless.

## SVGA (Z7, 2026-10-22)

Modes with 256 colors and up (ET4000 modes, VESA) go through the **framebuffer in
DDR**: the CPU writes via `main_memory` (states `FB_WRITE`/`FB_READ`,
banked window `A0000` or linear aperture at 248 MB) to `0x3F800000`,
the scaler (ascal) reads from there and uses the core's palette
(`MISTER_FB=1`, `MISTER_FB_PALETTE=1` in `core.tcl`). Costs ~160 ALMs.

- DOS: `SVGATEST.COM` (VESA `101h`, 640×480×256, 16×16 color patches) correct.
- Windows 95: driver **Tseng Labs ET4000**, 640×480, 800×600 and 1024×768
  with 256 colors work (smooth gray gradient).
- **Read buffer** (`make_pro.py`, `main_memory`): every read access to the
  framebuffer was a separate trip to the DDR (~42 cycles); Windows reads a lot
  and was sluggish. The most recently read 64-bit word stays buffered, CPU writes
  are tracked (only the CPU writes the framebuffer), the mailbox
  is excluded. Measured with `FBREAD.COM` (VESA 101h, 10 × 320 KB):

  | | without | with read buffer |
  |---|---|---|
  | Read bytewise | 1,420 KB/s | 3,640 KB/s |
  | Read dwordwise | 5,294 KB/s | 8,320 KB/s |
  | Write dword | 14,560 KB/s | 14,560 KB/s |

  The rest is the cost of the CPU's own uncached device access (~23 cycles per
  hit); prefetching more words would gain little.
- **Windows 95 with shared folder:** `C:\WINDOWS\SYSTEM.INI`, section
  `[386Enh]`: `EMMExclude=CE00-CFFF`. Otherwise Windows places its own code in the
  mailbox (which now looks like RAM); the z486 returns instructions fetched
  from a device page as `FF` → Windows hangs at the startup jingle.
  The same rule applies to the ao486 (there Windows would overwrite the mailbox).
- Screenshot (Main) also works in framebuffer mode (Main patch 0010,
  palette via UIO `0x4E`, `sys/de25/README.md`).
- Readability on the monitor: HDMI at 1080p (`video_mode=8`), for sharp
  pixels `vscale_mode=1` (integer; 1024×768 then 1:1 in the center).
- Color depths with the ET4000 driver (2 MB video memory): 256 colors up to
  1024×768, 16 bit up to 800×600, 24 bit up to 640×480 — the driver does not
  offer larger combinations (e.g. 1024×768×16 = 1.5 MB).
- Open: occasional 20–30 s pause during the Windows startup jingle
  (sporadic).

## x87 (Z7, 2026-10-22)

FPU enabled as upstream (`ENABLE_X87 = 1`): 43,159 ALMs (92%), 282 M20K, timing
met at 85 MHz. Adaptations (`make_pro.py`): the three ROMs
(`x87_ucode_rom`, `x87_command_rom`, `x87_logexp_rom`) moved from M10K to M20K,
contents still from the `.mif` files; the stack `x87_stack_mem` (8 × 80 bit, two
write ports) as registers via the vendor-neutral branch — Agilex 5
does not support BIDIR_DUAL_PORT with OLD_DATA.

`FPUTEST.COM` (test floppy): FPU detected; π, √2, sin(1), cos(1), ln(2),
1/3, atan(1) bit-exact; FMUL ~9 M/s, FDIV ~1.3 M/s (in the range of a
486DX2-66).

**Quake 1.06 shareware** (`quake106.zip`, MD5 `8cee4d03…1357`, unpacked in the container
with `lhasa`, as `quake.vhd` on IDE 0-1): runs under Win95 DOS
("Command prompt only"), `timedemo demo1` = **8.3 fps** (320×200; a real
486DX2-66 manages ~8–10). Win95 DOS sets no `BLASTER` and loads no
mouse driver — startup file `Q.BAT`: `set BLASTER=A220 I5 D1 H5 P330 T6`,
`CTMOUSE` (from FreeDOS), `QUAKE`.
Sound and mouse work with that. "MSCDEX not loaded, Music is disabled" is
normal: Quake's music consists of the CD audio tracks of the full version (the shareware has none).

**FreeDOS test disk:** `vinfo /m` (V8Power 2021) reports a 486 without
CPUID as an **80186** (bug in vinfo, fixed upstream in 2025, commit
`ccaff7ac`) — `FDAUTO.BAT` then takes the 8086 branch: no mouse, no CD.
Fix in `C:\FDAUTO.BAT` after `if errorlevel 2 goto Support286`:
`if errorlevel 1 goto Support386`; German keyboard: `keyb gr` before the
`vinfo` line. (The z486 computes `SHR` with CL=32 and `PUSH SP` correctly,
verified in `debug`.)

## Adaptations (`make_pro.py`, reasons given there)

| File | Change |
|---|---|
| `z486_mister.sv` | without x87; IOPLL `pll_z486` (`pll` is already the name of the HPS system's PLL module); `SDRAM_CLK` 90° via `sdram_clk_ddio` (phase window `cores/sdram486test`); LFB inputs as in `sys/emu_ports.vh`; **without `assign gamma_bus = 'z;`** |
| `src/memory/sdram.v` | Quartus Pro: declaration before use, DQ output register without enable (I/O register) |
| `src/z486/*` | microcode ROM inferred (altsyncram with clock1 forbidden on Agilex), `ramstyle` M20K, net type directive |
| `src/common/dpram.v` | `no_rw_check`, port B synchronous (otherwise logic or a duplicated RAM) |
| `src/soc/sound/sound.v`, `hps_ext.v`, `cdda.v`, `saa1099.sv` | Quartus Pro pitfalls 16788/16754, net type directive |
| `src/z486/x87/*_rom.sv`, `x87_stack_mem.sv` | M10K → M20K; stack as registers (BIDIR + OLD_DATA forbidden on Agilex 5) |
| `src/z486/z486_pkg.sv`, `l1_cache.sv`, `src/memory/main_memory.sv` | mailbox `CE000–CFFFF` as a device page into the DDR (shared folder, see below); in `main_memory` declarations moved before first use (Questa) |

The files that include `z486_platform.svh` are placed unchanged in `pro/`
so that `include` finds the adapted version (it searches the folder of the
including file first) — this way the project does not need `VERILOG_CU_MODE MFCU`,
which would also affect all sys files.

## Pitfalls

- **Tri-state drivers on internal buses:** `assign gamma_bus = 'z;` alongside
  the real drivers (`hps_io`, `gamma_corr`) made Quartus Pro resolve the bus
  incorrectly (warnings 13034/13035/13028) — CPU and BIOS ran, the
  picture stayed black. Check for 1303x after every build.
- **Main crashed with SIGBUS** (`x86_init`): `memset` and file loading directly
  into the `/dev/mem` mapping of the DDR window (device memory) — as with the
  C64 (patch 0005); Main patch 0006.
- Diagnostics without a UART: LED0 PLL, LED2 first CPU instruction, LED4 BIOS copied from
  the DDR, LED6 sys PLL. The z486's debug UART (BIOS messages) is not
  connected to anything in our setup.
