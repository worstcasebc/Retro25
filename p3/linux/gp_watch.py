#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""gp_watch.py — beobachtet den Handshake zwischen Main und FPGA (Fehlersuche).

Aufruf (als root):  sudo python3 gp_watch.py [Anzahl]
Liest mehrmals hintereinander:
  GPO  (hps_gp_bridge 0x2001_0100, Wort 0): was Main zuletzt geschrieben hat,
       Bit 17 = Strobe, Bits 20/19/18 = SS2/SS1/SS0 (Befehl an Core/sys/OSD)
  GPI  (Wort 1): was Main liest, Bit 17 = Quittung (io_ack)
  STATUS der Brücke (Wort 2): Bit 0 clk_sys läuft, Bit 1 Zeitgrenze erreicht
  video_debug-Status (0x2001_4000, Wort 11): Bit 14 io_wait, 15 vs_wait,
       16 io_ack im FPGA, 17 io_uio
Hängt Main in fpga_spi, sieht man hier, ob Strobe und Quittung auseinanderlaufen.
"""
import mmap
import os
import struct
import sys
import time

GP_BASE = 0x2001_0100
VD_BASE = 0x2001_4000


def main() -> int:
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
    page = GP_BASE & ~0xFFF
    gp = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ, offset=page)
    vd = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ, offset=VD_BASE)
    off = GP_BASE - page
    rd = lambda m, o: struct.unpack_from("<I", m, o)[0]
    print("   GPO        Strobe SS2..0  GPI        Ack   Brücke  FPGA: io_wait vs_wait io_ack io_uio")
    for _ in range(n):
        gpo = rd(gp, off + 0)
        gpi = rd(gp, off + 4)
        st = rd(gp, off + 8)
        vs = rd(vd, 4 * 11)
        print(f"   {gpo:08X}   {(gpo >> 17) & 1}      {(gpo >> 18) & 7:03b}   "
              f"{gpi:08X}   {(gpi >> 17) & 1}     {st & 3:02b}      "
              f"{(vs >> 14) & 1}       {(vs >> 15) & 1}       {(vs >> 16) & 1}      {(vs >> 17) & 1}")
        time.sleep(0.2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
