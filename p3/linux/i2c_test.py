#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""i2c_test.py — I2C-Master im FPGA prüfen (sys/de25/i2c_master_de25.v).

Aufruf (als root, Main sollte dabei nicht laufen):
  sudo python3 i2c_test.py            ADV7513-Kennung und einige Register lesen
  sudo python3 i2c_test.py rd REG     ein Register des ADV7513 (0x39) lesen
  sudo python3 i2c_test.py wr REG VAL ein Register schreiben
Das Programm übernimmt den Bus (own = 1) und gibt ihn am Ende im vorigen
Zustand zurück. Register bei physisch 0x2001_6000 (disk_m0 + 0x2000).
"""
import ctypes
import mmap
import os
import struct
import sys
import time

BASE = 0x2001_6000
ADV = 0x39
START, STOP, READ, NACK = 1 << 8, 1 << 9, 1 << 10, 1 << 11


class I2C:
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

    def cmd(self, c):
        # Erst warten, bis busy sichtbar wird (ein Byte dauert >= 90 µs,
        # ein Lesezugriff nur wenige µs), dann bis busy wieder weg ist: so
        # gilt ein veralteter Status von vor dem Befehl nicht als "fertig".
        self.wr(0, c)
        t0 = time.time()
        seen = False
        while True:
            st = self.rd(0)
            if st & 0x100:
                seen = True
            elif seen:
                return st
            if time.time() - t0 > 0.05:
                raise TimeoutError(f"I2C-Befehl 0x{c:03X}: busy {'bleibt' if seen else 'kam nie'}")

    def reg_read(self, dev, reg):
        if self.cmd(START | dev << 1) & 0x200:
            self.cmd(START | STOP | 0xFF)
            raise IOError(f"Gerät 0x{dev:02X} antwortet nicht")
        self.cmd(reg)
        self.cmd(START | dev << 1 | 1)
        return self.cmd(READ | NACK | STOP) & 0xFF

    def reg_write(self, dev, reg, val):
        if self.cmd(START | dev << 1) & 0x200:
            self.cmd(START | STOP | 0xFF)
            raise IOError(f"Gerät 0x{dev:02X} antwortet nicht")
        self.cmd(reg)
        if self.cmd(STOP | val) & 0x200:
            raise IOError("NACK beim Datenbyte")


def main():
    bus = I2C()
    st = bus.rd(0)
    if st >> 24 != 0x49:
        print(f"Status 0x{st:08X}: kein I2C-Master im Core")
        return 1
    ctrl_before = bus.rd(1)
    print(f"Status 0x{st:08X}, ctrl 0x{ctrl_before:08X} (own={ctrl_before & 1})")
    bus.wr(1, ctrl_before | 1)
    try:
        if len(sys.argv) >= 3 and sys.argv[1] == "rd":
            reg = int(sys.argv[2], 0)
            print(f"ADV7513[0x{reg:02X}] = 0x{bus.reg_read(ADV, reg):02X}")
        elif len(sys.argv) >= 4 and sys.argv[1] == "wr":
            bus.reg_write(ADV, int(sys.argv[2], 0), int(sys.argv[3], 0))
        else:
            t0 = time.time()
            rev = bus.reg_read(ADV, 0x00)
            idh, idl = bus.reg_read(ADV, 0xF5), bus.reg_read(ADV, 0xF6)
            dt = time.time() - t0
            print(f"Chip-Revision 0x{rev:02X}, Chip-ID 0x{idh:02X}{idl:02X} (erwartet 0x7511), "
                  f"3 Lesezugriffe in {dt * 1000:.1f} ms")
            for reg in (0x41, 0x42, 0x15, 0x16, 0xAF):
                print(f"  [0x{reg:02X}] = 0x{bus.reg_read(ADV, reg):02X}")
            try:
                bus.reg_read(0x3A, 0x00)
                print("FEHLER: fremde Adresse 0x3A hat geantwortet")
            except IOError:
                print("fremde Adresse 0x3A: kein ACK (richtig)")
    finally:
        bus.wr(1, ctrl_before)
    return 0


if __name__ == "__main__":
    sys.exit(main())
