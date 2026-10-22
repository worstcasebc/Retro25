#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prüft die gp-Register (hps_gp_bridge) eines geladenen Retro25-Cores.

Aufruf (als root, Core geladen, FPGA-Manager-Zustand "operating"):
    sudo python3 gp_check.py

Liest wie Main_MiSTer über /dev/mem an der LW-Bridge:
    0x2001_0100  GPO   (gp_out, schreiben)
    0x2001_0104  GPI   (gp_in, lesen)
    0x2001_0108  STATUS der Brücke (Bit 0 clk_sys läuft, Bit 1 Zeitgrenze)
    0x2001_010C  ID der Brücke ("R25G")
Erwartet: ID R25G, clk_sys läuft, mit gp_out[31] = 0 die MiSTer-Kennung
0x5CA623 und den Core-Typ 0xA4, mit gp_out[31] = 1 io_ver = 1.
Läßt den Core danach im Normalbetrieb (gp_out = 0x8000_0000).
"""
import mmap
import os
import struct
import sys
from pathlib import Path

BASE = 0x2001_0000
OFF = 0x100
MGR = Path("/sys/class/fpga_manager/fpga0/state")


def main() -> int:
    if os.geteuid() != 0:
        sys.exit("Bitte mit sudo starten.")
    if MGR.exists() and MGR.read_text().strip() != "operating":
        sys.exit(f"FPGA nicht im Betrieb ({MGR.read_text().strip()}) — Brücke wird nicht gelesen.")
    fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=BASE)
    rd = lambda o: struct.unpack_from("<I", m, OFF + o)[0]
    wr = lambda o, v: struct.pack_into("<I", m, OFF + o, v)

    errors = 0

    def check(name: str, ok: bool, value: int) -> None:
        nonlocal errors
        print(f"{'ok  ' if ok else 'FEHLER'} {name}: 0x{value:08x}")
        errors += 0 if ok else 1

    ident = rd(0xC)
    check("ID der Brücke (R25G = 0x52323547)", ident == 0x5232_3547, ident)
    status = rd(0x8)
    check("STATUS (Bit 0: clk_sys läuft)", status & 1 == 1, status)

    wr(0x0, 0x0000_0000)
    gpi = rd(0x4)
    check("Kennung bei gp_out[31]=0 (0x5CA623xx)", gpi >> 8 == 0x5CA623, gpi)
    print(f"       Core-Typ: 0x{gpi & 0xFF:02x} (0xA4 = gewöhnlicher Core)")

    wr(0x0, 0x8000_0000)
    gpi = rd(0x4)
    check("GPI im Normalbetrieb: Bit 31 = 0", gpi >> 31 == 0, gpi)
    check("io_ver = GPI[19:18] = 1", (gpi >> 18) & 3 == 1, gpi)
    status = rd(0x8)
    check("STATUS ohne Zeitüberschreitung (Bit 1 = 0)", status & 2 == 0, status)

    m.close()
    os.close(fd)
    print("\nAlles in Ordnung." if errors == 0 else f"\n{errors} Fehler.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
