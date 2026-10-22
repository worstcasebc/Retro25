# linux/system — Board system settings (P3a)

Goal: a hard reset (a hang during core development, power loss) should no
longer be able to damage the system on the SD card. On 2026-10-16 a series
of such resets had destroyed the root file system (superblock, 16 programs
in `/usr/bin`; recovered with `tools/sd_rescue.py`).

Principle: the system is kept read-only ("in the vault"); only the data
partition and RAM folders are written. Linux writes nothing to a partition
mounted `ro` — a reset finds no half-finished write there. Damage cannot be
ruled out completely: an SD card's controller reorganizes data internally
and, in rare cases, a reset in the middle of a write can also hit
neighboring data.

## SD card layout

| Partition | Size | Contents | Mounted |
|---|---|---|---|
| `mmcblk0p1` | 300 MB, FAT | Bootloader, kernel, start core (`retro25/core.rbf`) | no |
| `mmcblk0p2` | 8 GiB, ext4 | Ubuntu (root) | `/`, **ro** |
| `mmcblk0p3` | 20.8 GiB, ext4, label `retro25data` | `/media/fat` (Main, cores, configuration, save games), `/media/fat/retro25` (staging, `~/retro25` points there) | `/media/fat`, rw |

In RAM (empty after a reboot): `/tmp`, `/var/tmp`, `/var/log` (including
the journal, at most 32 MB), `/var/lib/NetworkManager`,
`/var/lib/systemd/timesync`, `/var/lib/logrotate`, the PulseAudio databases
(`~/.config/pulse`) and the currently loaded core
(`/run/retro25-fw/retro25/main.core.rbf`).

## Files

| File | Destination | Purpose |
|---|---|---|
| `install.sh` | — | installs everything (switches to rw and back by itself if needed) |
| `fstab` | `/etc/fstab` | root ro, data partition, RAM folders |
| `tmpfiles-retro25.conf` | `/etc/tmpfiles.d/retro25.conf` | permissions of the RAM folders, firmware search path `/run/retro25-fw` |
| `journald-retro25.conf` | `/etc/systemd/journald.conf.d/` | journal in RAM only |
| `90-retro25.conf` | `/etc/sysctl.d/` | Magic SysRq fully enabled |
| `retro25-rw` | `/usr/local/sbin/retro25-rw`, `retro25-ro` | switch the root for maintenance |
| `rw-offen.py` | `/usr/local/sbin/retro25-rw-offen` | shows who is keeping the root writable |
| `retro25-usb` | `/usr/local/sbin/` | mount/unmount USB drives (`/media/usb0..5`) |
| `retro25-usb@.service` | `/etc/systemd/system/` | one service per device, bound to the device (unplugging = unmounting) |
| `99-retro25-usb.rules` | `/etc/udev/rules.d/` | starts the service when a device is plugged in |

In addition, `install.sh` disables timers and services that want to write
to the root: apt updates, motd-news, man-db, dpkg-db-backup, e2scrub,
fstrim, apport.

## USB drives (games)

As on MiSTer: every USB drive with FAT or ext4 is mounted on plug-in at the
first free `/media/usb0..5` (read-write, owner `terasic`, FAT with `flush` —
writes go to the stick immediately) and unmounted again when unplugged. The
kernel does not support exFAT or NTFS. Main looks for games on USB first
(`<drive>/C64` or `<drive>/games/C64`), then in `/media/fat/games/C64`.
Never unplug a stick while the core is writing to a floppy.
To check: `findmnt | grep usb`, `systemctl status 'retro25-usb@*'`,
`journalctl -u 'retro25-usb@*'`.

## Maintenance

```
sudo retro25-rw          # root writable (apt, files in /etc …)
sudo retro25-ro          # read-only again; a reboot does it too
sudo retro25-rw-offen    # if retro25-ro reports "busy": who is still writing?
```

`linux/main/install.sh` and `linux/system/install.sh` switch by themselves.
Copy files for the board via `scp` to `~/retro25/` (it is on the data
partition).

## Hangs: clean reboot instead of reset

As long as the kernel is still printing messages (e.g. `arm-smmu-v3 …
CMD_SYNC timeout`), send Magic SysRq over the serial console (COM11,
115200): BREAK, then the key — `w`/`l` for diagnostics, then `s` (sync),
`u` (remount everything ro), `b` (reboot). Only if nothing responds at all:
the reset button.

## Network

U-Boot randomizes the Ethernet MAC address on every boot (no stored
address); as a result, the router assigned a different IP each time.
NetworkManager therefore sets a fixed, locally administered address
(`nmcli con modify "Wired connection 1|2" 802-3-ethernet.cloned-mac-address
a2:d3:33:94:7a:42`, in `/etc/NetworkManager`); the board is now always
reachable at the same address (most recently 192.168.178.125).

## Backup

Image of the entire card (card in the PC, administrator PowerShell):
`python tools/sd_rescue.py backup DISK F:\retro25-sd\karte.img` —
restore with balenaEtcher, Rufus or similar.
