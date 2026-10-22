#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# p0_check.sh — Vorprüfung für P0 auf dem Board. Ändert nichts.
#
# Aufruf: sudo bash p0_check.sh | tee p0_check.txt
#
# Sammelt, was der Core-Wechsel aus Linux braucht: FPGA-Manager-Treiber,
# configfs-Overlays, Werkzeuge (dtc, mkimage), Lage des DDR, /dev/mem,
# U-Boot-Befehl "fpga load" und das bisherige Bootskript. Läuft auch mit dem
# heutigen C64-Design (FPGA-first). Die Ausgabe bitte komplett zurückgeben.

echo "=== System"
uname -a
cat /etc/os-release 2>/dev/null | grep PRETTY

echo; echo "=== Module für den FPGA-Manager"
for m in stratix10-soc of-fpga-region fpga-region fpga-bridge altera-freeze-bridge; do
    if modinfo "$m" >/dev/null 2>&1; then echo "vorhanden: $m"; else echo "FEHLT:     $m"; fi
done
lsmod | grep -i -E "fpga|stratix|region|bridge" || echo "(keines geladen)"

echo; echo "=== FPGA-Manager und Region"
ls -l /sys/class/fpga_manager/ 2>/dev/null || echo "kein /sys/class/fpga_manager"
for f in /sys/class/fpga_manager/*/{name,state,status}; do [ -e "$f" ] && echo "$f: $(cat "$f")"; done
ls /sys/class/fpga_region/ /sys/class/fpga_bridge/ 2>/dev/null
ls /proc/device-tree/ | grep -i -E "fpga|region" || true
[ -d /proc/device-tree/fpga-region ] && ls /proc/device-tree/fpga-region

echo; echo "=== configfs-Overlays"
mount | grep configfs || echo "configfs nicht eingehängt"
ls -d /sys/kernel/config/device-tree/overlays 2>/dev/null || echo "kein /sys/kernel/config/device-tree/overlays"

echo; echo "=== Werkzeuge"
for t in dtc mkimage dumpimage python3; do printf "%-10s %s\n" "$t" "$(command -v $t || echo FEHLT)"; done

echo; echo "=== Speicher (System RAM, reserviert)"
grep -i -E "System RAM|reserved|svc" /proc/iomem
ls /proc/device-tree/reserved-memory/ 2>/dev/null

echo; echo "=== /dev/mem und LW-Bridge (sysid bei 0x2001_0000)"
python3 - <<'EOF'
import mmap, os, struct
try:
    f = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
    m = mmap.mmap(f, 4096, mmap.MAP_SHARED, mmap.PROT_READ, offset=0x20010000)
    print("sysid  = 0x%08x" % struct.unpack_from("<I", m, 0)[0])
    print("0x100  = 0x%08x" % struct.unpack_from("<I", m, 0x100)[0])
except Exception as e:
    print("Fehler:", e)
EOF

echo; echo "=== Dienst c64d (muss für P0 gestoppt sein)"
systemctl is-enabled c64d 2>/dev/null; systemctl is-active c64d 2>/dev/null

echo; echo "=== Boot-Partition"
BOOT=$(findmnt -n -o TARGET /dev/mmcblk0p1 2>/dev/null)
if [ -z "$BOOT" ]; then
    BOOT=/tmp/p0_boot; mkdir -p $BOOT; mount -o ro /dev/mmcblk0p1 $BOOT && UMOUNT=1
fi
echo "eingehängt unter: $BOOT"
ls -la "$BOOT"
echo "--- U-Boot kennt 'fpga load'?"
grep -a -o -E "fpga (load|info)[^\"]{0,60}" "$BOOT/u-boot.itb" | sort -u | head -5 || echo "(kein Treffer)"
if command -v dumpimage >/dev/null; then
    echo "--- Bootskript"
    dumpimage -l "$BOOT/boot.scr.uimg"
    dumpimage -T flat_dt -p 0 -o /tmp/p0_uboot.txt "$BOOT/boot.scr.uimg" >/dev/null 2>&1 && cat /tmp/p0_uboot.txt
else
    echo "--- Bootskript (ohne dumpimage, lesbare Teile)"
    strings "$BOOT/boot.scr.uimg"
fi
[ -n "$UMOUNT" ] && umount $BOOT
echo; echo "=== Ende"
