# linux/main — Main_MiSTer on the DE25-Nano

Main_MiSTer is MiSTer's Linux program: it draws the menu (OSD), reads the
keyboard and gamepads, loads cores and feeds in disk images. The original
(`linux/vendor/main_mister`, unmodified, `tools/fetch_main.py`) is written for
the 32-bit ARM of the DE10-Nano. This directory holds what it needs for the
DE25-Nano (aarch64, Agilex 5).

## Layout

| Path | Purpose |
|---|---|
| `build.sh` | Assemble the source tree (vendor + patches + de25/) and build |
| `docker/Dockerfile` | Build environment: Ubuntu 22.04 arm64, same as on the board (for `tools/build_main.py`) |
| `Makefile` | like the original, but native gcc and Ubuntu libraries |
| `de25/fpga_io.cpp` | **new:** gp_out/gp_in via `hps_gp_bridge`, core loading via overlay, Wi-Fi hook |
| `de25/shmem.cpp` | **new:** maps only known addresses (parameter page as a file, DDR window); `shmem_put`/`shmem_get` copy with aligned accesses (via `/dev/mem` the window can only be mapped as device memory: `memset`/`memcpy` raise SIGBUS there); addresses in the middle of a page work (mapped from the start of the page, `mmap` requires page boundaries — otherwise EINVAL for x86_share `0x300CE004`) |
| `de25/smbus.cpp` | **new:** I2C to the HDMI transmitter via the I2C master in the FPGA instead of `/dev/i2c-N` |
| `patches/0001-…` | Amiga disk structures with 32-bit fields (also affects IDE/z486) |
| `patches/0002-…` | Main on CPU 3, helper thread on CPU 2 (the Cortex-A76 cores) |
| `patches/0003-…` | three places that only compile correctly on 32 bit |
| `patches/0004-…` | integer HDMI PLL calculation (N/M/C) for the Agilex 5 IOPLL |
| `patches/0005-…` | C64: build the disk image (G64) in RAM first, then copy it into DDR via `shmem_put` (otherwise SIGBUS when inserting a D64) |
| `patches/0006-…` | x86 (z486/ao486): BIOS ROMs and memory fill into DDR via `shmem_put` instead of `memset`/file loading into the mapping (otherwise SIGBUS in `x86_init`) |
| `patches/0007-…` | Mouse movement directly from evdev when `/dev/input/mouseN` is missing (Terasic kernel without `CONFIG_INPUT_MOUSEDEV`; before, only the buttons came through) |
| `patches/0008-…` | Hard disk/floppy images (`ide_img_mount`) without `O_SYNC`; `fsync` after 1 s without writes and before an image change. With `O_SYNC`, stick and SD card managed only ~150 writes/s (Win95 ~40 KB/s, now ~8–10× faster) |
| `patches/0009-…` | Shared folder (x86_share): fetch MISTERFS frames into normal memory via `shmem_get`, process them there, write the reply back via `shmem_put` (directly in the DDR window → SIGBUS, like 0005/0006) |
| `patches/0010-…` | Screenshot in a core's framebuffer mode (`MISTER_FB`): image taken directly from DDR (base/line length from `UIO_GET_FB_PAR`), at 8 bpp the palette via the new UIO command `0x4E` (shadow copy in `sys_top_de25`); before, only stripes from the scaler's VGA input |
| `board/retro25-main.dts` | Overlay that Main uses to load a core |
| `board/retro25-switch-hook` | turns Wi-Fi off and back on during a core switch (P0) |
| `board/retro25-main.service` | systemd service: starts Main at boot, restarts it after a crash |
| `install.sh` | sets everything up on the board (`/media/fat`, overlay, hook, modules) |

Analogy: the third-party code is a piece of furniture you bought. We don't
saw into it; instead we put a list of changes next to it (patches) and swap
out two parts completely (de25/). When a new version comes out, you only
need to check the list.

## Building

**On the PC (recommended):** in an arm64 container with the same Ubuntu as
on the board. Docker Desktop runs it via QEMU; the result runs unmodified on
the board.

```
python tools/build_main.py                                # -> linux/main/build/MiSTer
python tools/build_main.py --deploy terasic@192.168.178.125   # + copy to ~/retro25/
```

On first run the script builds the image `retro25-arm64` from
`docker/Dockerfile`, copies the sources into the Docker volume
`retro25-build` and runs `build.sh` there. Why a volume? Working directly
from the Windows folder makes every file access in the QEMU container very
slow; in addition, the object files stay in the volume, so a second build
only recompiles what changed. Options: `--clean` (rebuild everything),
`--rebuild-image`, further make arguments after `--` (e.g. `-- DEBUG=1`).
Changes to the Makefile do not trigger a recompile → `--clean`.

**On the board:**

```
sudo apt install build-essential libimlib2-dev libfreetype-dev libpng-dev \
                 libbz2-dev zlib1g-dev libbluetooth-dev
cd linux/main && ./build.sh          # -> build/src/bin/MiSTer
```

At runtime the board only needs `libimlib2` (Ubuntu already has the other
libraries).

## Setup and starting

```
cd ~/retro25 && sudo ./install.sh testpattern.core.rbf   # after --deploy; add the core file
```

`install.sh` sets Main up as the service `retro25-main` and starts it — as
on MiSTer, Main then always runs, including after every reboot. Main is the
interpreter between the USB keyboard and the core: without Main there is
neither F12 nor any keyboard input in the core.

```
systemctl status retro25-main          # is Main running?
journalctl -u retro25-main -f          # follow the output
sudo systemctl stop retro25-main       # before starting it by hand
sudo /media/fat/MiSTer /media/fat/_Retro25/Testpattern.rbf
```

The start core is loaded by U-Boot (`retro25/core.rbf` on the boot
partition); Main gets its path from `RETRO25_CORE` in `/etc/default/retro25`
(on the first `install.sh`, the first core given). The two must match.

Main only starts if a Retro25 core (with `hps_gp_bridge`) is running in the
FPGA — otherwise it reports "FPGA is uninitialized" and exits; the service
retries every 3 s.

**Remote control:** Main reads commands from the FIFO `/dev/MiSTer_cmd`. The
service runs with `UMask=0000` so that the FIFO stays writable for everyone
after every start (including after every core switch, when Main recreates
it) — this way it works without `sudo`, e.g. for tests via `ssh`:

```
echo "load_core /media/fat/_Retro25/Memtest.rbf" > /dev/MiSTer_cmd
echo screenshot > /dev/MiSTer_cmd      # PNG in /media/fat/screenshots/<CORE>/
```

`/media/fat/_Retro25` and `/media/fat/games` (games per core, e.g.
`games/C64`) belong to the user `terasic` (copy files in without `sudo`);
`install.sh` creates them. Cores written by `install.sh` belong to root.

## Differences from the DE10-Nano (as of P3)

- **Loading a core** takes ~2 s (kernel FPGA manager via the SDM) instead of
  Main doing it itself through the Cyclone V's FPGA manager.
- **DDR lock before loading:** Main halts all three DDR ports in the FPGA
  and waits until they are idle (`f2s_halt()` in `de25/fpga_io.cpp`,
  register `0x2001_7000`, `sys/de25/f2s_halt_de25.v`). Reloading in the
  middle of an F2SDRAM access would hang the SMMU and with it Linux. If the
  ports do not become idle, the old core stays ("DDR busy" in the OSD). A
  core without the register (older version) is loaded anyway, with a
  warning.
- **Menu core:** as on MiSTer, `/media/fat/menu.rbf`; the other cores live
  in `/media/fat/_Retro25/` (`sudo ./install.sh menu.core.rbf X.core.rbf`).
  U-Boot loads it as the start core (`boot/retro25-bootscr.sh install
  menu.core.rbf`); `/etc/default/retro25` then contains `RETRO25_CORE=`
  (empty, Main detects the menu by itself).
- **HDMI transmitter:** it is connected to FPGA pins, not to the HPS I2C.
  Main reaches it through the I2C master in the FPGA (`0x2001_6000`):
  `de25/smbus.cpp` replaces `smbus.cpp` with the same interface; there is
  exactly one bus. On the first `i2c_open` Main takes over the bus; until
  then, `hdmi_config` in the FPGA sets the transmitter up to show a picture.
- **DDR window** (scaler, framebuffer, core memory, save states): MiSTer
  addresses `0x2000_0000–0x3FFF_FFFF` are physically located at
  `0xA000_0000–0xBFFF_FFFF` (since P3, reserved by U-Boot);
  `de25/shmem.cpp` translates. `shmem_map()` does not return other
  addresses.
- **Video mode:** `video_mode` takes effect (since P3 step 4). The Agilex 5
  HDMI PLL only divides by integers; patch `0004-hdmi-pll-ganzzahlig.patch`
  calculates N/M/C instead of M/K (deviation mostly 0 ppm, 640×480:
  +17 ppm). Missing are `vsync_adjust=2` (low-latency PLL readjustment,
  fractional) and `direct_video`. `install.sh` sets `video_mode=0` if none
  is set.
- **Core file in RAM:** Main writes the core to be loaded to
  `/run/retro25-fw/retro25/main.core.rbf` and sets the kernel's firmware
  search path to `/run/retro25-fw` (the root has been read-only since P3a,
  `linux/system/`). The overlay `main.dtbo` stays in `/lib/firmware`.
- **Reboot** via `/sbin/reboot`; U-Boot then loads the start core.
- **After a core switch** Main replaces itself via `execl` instead of
  starting a detached successor via a double `fork` like the original —
  otherwise systemd would lose track of the process.
- **No effect:** `fpga_core_read/write` (not used by any part of Main),
  loading with configuration (`cfg`, U-Boot environment in DDR).
- Kernel without `uinput`, `hidraw`, `joydev`: Main reports "Unable to open
  /dev/uinput"; keyboard and gamepads work anyway (evdev).
