#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""ddr_check.py — prüft von Linux aus, was ddr_test im FPGA ins DDR geschrieben hat (P3, 2c).

Aufruf (als root):  sudo python3 ddr_check.py [Wörter]
ddr_test (cores/testpattern) schreibt 16384 64-bit-Wörter ab MiSTer-Adresse
0x3000_0000 = physisch 0xB000_0000 (reserviertes Fenster). Wort i:
    {i ^ 0xA5A5_5A5A, i ^ seed}   (oberes / unteres 32-bit-Halbwort)
seed wechselt mit jedem Lauf; das Skript liest es aus Wort 0 (i = 0).
"""
import mmap
import os
import struct
import sys

PHYS = 0xB000_0000
WORDS = int(sys.argv[1]) if len(sys.argv) > 1 else 16384


def main() -> int:
    size = WORDS * 8
    fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
    m = mmap.mmap(fd, (size + 4095) & ~4095, mmap.MAP_SHARED, mmap.PROT_READ, offset=PHYS)
    lo0, hi0 = struct.unpack_from("<II", m, 0)
    seed = lo0
    print(f"0x{PHYS:08X}: Wort 0 = 0x{hi0:08X}_{lo0:08X} -> seed 0x{seed:08X}")
    if hi0 != 0xA5A5_5A5A:
        print("  Oberes Halbwort von Wort 0 ist nicht 0xA5A5_5A5A — ddr_test hat hier "
              "(noch) nichts geschrieben oder schreibt woanders hin.")
        return 1
    errors = 0
    for i in range(WORDS):
        lo, hi = struct.unpack_from("<II", m, i * 8)
        if hi != i ^ 0xA5A5_5A5A or lo != i ^ seed:
            if errors < 8:
                print(f"  Fehler Wort {i} (0x{PHYS + i * 8:08X}): 0x{hi:08X}_{lo:08X}, "
                      f"erwartet 0x{i ^ 0xA5A5_5A5A:08X}_{i ^ seed:08X}")
            errors += 1
    print(f"{WORDS} Wörter geprüft, {errors} Fehler")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
