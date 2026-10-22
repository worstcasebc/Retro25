#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""pll_cfg.py — HDMI-PLL-Umstellung prüfen (sys/de25/pll_cfg_de25.v).

Aufruf (als root):
  sudo python3 pll_cfg.py status          Status, Zähler, Schattenregister
  sudo python3 pll_cfg.py dump            PLL-Register lesen und deuten
  sudo python3 pll_cfg.py rd OFS          ein Register roh lesen (Byte-Offset,
                                          z. B. 0x40), mit Byte-Aufzeichnung
  sudo python3 pll_cfg.py wr OFS WERT     ein Register roh schreiben
  sudo python3 pll_cfg.py ctrl WERT       Steuerbits setzen (siehe RTL-Kopf)
  sudo python3 pll_cfg.py set N M C       PLL umstellen (ganzzahlig)
  sudo python3 pll_cfg.py mhz F           PLL für F MHz rechnen und umstellen
Debug-Register bei physisch 0x2001_5000 (disk_m0 + 0x1000).
"""
import ctypes
import mmap
import os
import struct
import sys
import time

BASE = 0x2001_5000
REF_MHZ = 50.0


class Regs:
    def __init__(self):
        fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        self.m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=BASE)
        os.close(fd)
        # Zugriffe als echte 32-bit-Lese-/Schreibbefehle: struct.pack_into
        # auf dem mmap kann in Teilzugriffe zerfallen, die Register sehen
        # dann nur einzelne Bytes.
        self.r = (ctypes.c_uint32 * 1024).from_buffer(self.m)

    def rd(self, i):
        return self.r[i]

    def wr(self, i, v):
        self.r[i] = v & 0xFFFF_FFFF

    def wait_idle(self, timeout=1.0):
        t0 = time.time()
        while self.rd(0) & 1:
            if time.time() - t0 > timeout:
                raise TimeoutError("pll_cfg_de25 bleibt busy")
        return self.rd(0)

    def raw_read(self, ofs):
        self.wr(2, ofs)
        self.wr(4, 0)
        self.wait_idle()
        return self.rd(3)

    def raw_write(self, ofs, val):
        self.wr(2, ofs)
        self.wr(3, val)
        self.wait_idle()

    def cap(self):
        b = b"".join(struct.pack("<I", self.rd(i)) for i in (5, 6, 7)) + struct.pack("<I", self.rd(13))[:2]
        return b


def pll_div(d):   # Cyclone-V-Format wie getPLLdiv in Main
    if d == 1:
        return 0x10000
    if d & 1:
        return 0x20000 | ((d // 2 + 1) << 8) | (d // 2)
    return ((d // 2) << 8) | (d // 2)


def cyc_total(v):
    return 1 if v & 0x10000 else ((v >> 8) & 0xFF) + (v & 0xFF)


def status(r):
    st = r.rd(0)
    if st >> 16 != 0x504C:
        print(f"Kennung 0x{st >> 16:04X} statt 0x504C — Core ohne pll_cfg_de25?")
        return False
    cnt = r.rd(11)
    print(f"Status 0x{st:08X}: busy={st & 1} locked={(st >> 1) & 1} timeout={(st >> 2) & 1} "
          f"Prüffehler={(st >> 3) & 1} Zustand={(st >> 4) & 0xF}")
    print(f"ctrl 0x{r.rd(1):02X}; Läufe {cnt & 0xFF}, fertig {(cnt >> 8) & 0xFF}, Timeouts {(cnt >> 16) & 0xFF}, "
          f"Wiederholungen {(cnt >> 24) & 0xFF}")
    m, n, c = r.rd(8), r.rd(9), r.rd(10)
    print(f"Schatten: M={cyc_total(m)} (0x{m:05X}) N={cyc_total(n)} (0x{n:05X}) C={cyc_total(c)} (0x{c:05X})")
    return True


def decode_hl(v, hi_lo_shift, odd_bit, byp_bit):
    hi = v & 0xFF
    lo = (v >> hi_lo_shift) & 0xFF
    if (v >> byp_bit) & 1:
        return 1, hi, lo, "bypass"
    return hi + lo, hi, lo, "ungerade" if (v >> odd_bit) & 1 else ""


def dump(r):
    for ofs in (0x10, 0x40, 0x44, 0x48, 0x54, 0x58, 0x5C, 0x80, 0x88):
        print(f"0x{ofs:02X}: 0x{r.raw_read(ofs):08X}")
    v40 = r.raw_read(0x40)
    m = 1 if v40 >> 31 else (v40 >> 20) & 0x1FF
    n, *_ = decode_hl(v40, 9, 17, 8)
    v5c = r.raw_read(0x5C)
    c, *_ = decode_hl(v5c, 23, 31, 8)
    cp = (r.raw_read(0x44) >> 1) & 0x7FFF
    print(f"=> N={n} M={m} C={c}: VCO {REF_MHZ * m / n:.3f} MHz, Ausgang {REF_MHZ * m / n / c:.4f} MHz; "
          f"Ladungspumpe {cp >> 10:05b}_{(cp >> 5) & 31:05b}_{cp & 31:05b}")


def find_nmc(f):
    best = None
    for n in range(1, 6):
        for m in range(1, 321):
            vco = REF_MHZ * m / n
            if not 600 <= vco <= 3200:
                continue
            c = round(vco / f)
            if not 2 <= c <= 510:
                continue
            err = abs(vco / c - f)
            # gleiche Abweichung: höherer VCO bei gleichem N (wie Main)
            if best is None or err < best[0] - 1e-9 or (err < best[0] + 1e-9 and n == best[1]):
                best = (err, n, m, c)
    return best[1:]


def set_pll(r, n, m, c):
    r.wr(8, pll_div(m))
    r.wr(9, pll_div(n))
    r.wr(10, pll_div(c))
    before = r.rd(11)
    t0 = time.time()
    r.wr(12, 0)
    time.sleep(0.001)
    st = r.wait_idle(timeout=2.0)
    print(f"N={n} M={m} C={c} -> {REF_MHZ * m / n / c:.4f} MHz; Lauf {time.time() - t0:.3f} s, "
          f"locked={(st >> 1) & 1}, timeout={(st >> 2) & 1}, Zähler 0x{before:06X} -> 0x{r.rd(11):06X}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    r = Regs()
    cmd = sys.argv[1]
    if not status(r):
        return 1
    if cmd == "status":
        return 0
    if cmd == "dump":
        dump(r)
    elif cmd == "rd":
        ofs = int(sys.argv[2], 0)
        v = r.raw_read(ofs)
        print(f"0x{ofs:02X} = 0x{v:08X}; Bytes je Takt: {r.cap().hex(' ')}")
    elif cmd == "wr":
        r.raw_write(int(sys.argv[2], 0), int(sys.argv[3], 0))
    elif cmd == "ctrl":
        r.wr(1, int(sys.argv[2], 0))
        print(f"ctrl = 0x{r.rd(1):02X}")
    elif cmd == "set":
        set_pll(r, int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]))
    elif cmd == "mhz":
        n, m, c = find_nmc(float(sys.argv[2]))
        set_pll(r, n, m, c)
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
