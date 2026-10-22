#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""f2s_halt.py — DDR-Sperre vor dem Umladen prüfen (sys/de25/f2s_halt_de25.v).

Aufruf (als root):
  sudo python3 f2s_halt.py            Status lesen
  sudo python3 f2s_halt.py on         Sperre setzen, auf "leer" warten
  sudo python3 f2s_halt.py off        Sperre aufheben
Register bei physisch 0x2001_7000 (disk_m0 + 0x3000):
  W [0] halt; R [0] halt, [3:1] leer (ram1, ram2, vbuf), [31:16] 0x4844
"""
import ctypes
import mmap
import os
import sys
import time

BASE = 0x2001_7000


def main():
    fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=BASE)
    os.close(fd)
    r = (ctypes.c_uint32 * 1024).from_buffer(m)   # echte 32-bit-Zugriffe

    def show(st):
        idle = (st >> 1) & 7
        print(f"Status 0x{st:08X}: halt={st & 1} leer ram1={idle & 1} ram2={(idle >> 1) & 1} vbuf={idle >> 2}")

    st = r[0]
    if st >> 16 != 0x4844:
        print(f"Status 0x{st:08X}: keine DDR-Sperre im Core")
        return 1
    show(st)
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "on":
        t0 = time.time()
        r[0] = 1
        while (r[0] & 0xE) != 0xE and time.time() - t0 < 1.0:
            pass
        dt = time.time() - t0
        show(r[0])
        print(f"{'leer' if (r[0] & 0xE) == 0xE else 'NICHT leer'} nach {dt * 1000:.2f} ms")
    elif cmd == "off":
        r[0] = 0
        show(r[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
