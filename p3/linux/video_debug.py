#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""video_debug.py — liest die Messpunkte der Videokette (sys/de25/video_debug.v).

Aufruf (als root):  sudo python3 video_debug.py [Sekunden]
Liest die Zähler zweimal im Abstand von [Sekunden] (Standard 1) und zeigt
die Raten: Bilder/s und Zeilen/s an Core-Ausgang, ascal-Ein- und -Ausgang,
HDMI-Takt, vbuf-Zugriffe; dazu Statusbits und das Timing von Main.
Erwartung bei 720p60 überall: 60 Bilder/s, 43 200 Zeilen/s, 74,25 MHz.
"""
import mmap
import os
import struct
import sys
import time

BASE = 0x2001_4000
NAMES = ["ID", "Core VS", "Core DE", "ascal-Eingang DE", "ascal-Ausgang VS",
         "ascal-Ausgang DE", "HDMI-Takt/1024", "vbuf Schreibwörter",
         "vbuf Lesebefehle", "vbuf Lesewörter", "vbuf Wartetakte"]
STATUS = ["hdmi_pll_locked", "reset_req", "reset", "cfg_ready", "cfg_done",
          "cfg_set", "direct_video", "vga_fb", "FB_EN", "LFB_EN", "lowlat",
          "scaler_out", "HDMI_TX_VS", "HDMI_TX_DE", "io_wait", "vs_wait",
          "io_ack", "io_uio"]


def read_all(m):
    return [struct.unpack_from("<I", m, 4 * i)[0] for i in range(14)]


def main() -> int:
    dt = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0
    fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
    m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ, offset=BASE)
    a = read_all(m)
    if a[0] != 0x5232_3544:
        print(f"ID 0x{a[0]:08X} statt 0x52323544 ('R25D') — Core ohne video_debug?")
        return 1
    time.sleep(dt)
    b = read_all(m)
    for i in range(1, 11):
        rate = ((b[i] - a[i]) & 0xFFFF_FFFF) / dt
        extra = f"  = {rate * 1024 / 1e6:.2f} MHz" if i == 6 else ""
        print(f"{NAMES[i]:22s} {b[i]:10d}   {rate:12.1f}/s{extra}")
    st = b[11]
    print("Status:", ", ".join(f"{n}={(st >> k) & 1}" for k, n in enumerate(STATUS)))
    print(f"Timing von Main: WIDTH={b[12] & 0xFFF} HEIGHT={(b[12] >> 16) & 0xFFF} "
          f"HBP[3:0]={(b[12] >> 12) & 0xF} HFP[3:0]={(b[12] >> 28) & 0xF}")
    print(f"Befehlsparser (UIO): letztes Kommando 0x{(b[13] >> 8) & 0xFF:02X}, "
          f"Wort {b[13] & 0xFF}, Strobes (8 bit) {(b[13] >> 16) & 0xFF}, "
          f"Befehle 0x20 (8 bit) {(b[13] >> 24) & 0xFF}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
