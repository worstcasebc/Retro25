#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""f2sdram_probe.py — Gegenstelle für den F2SDRAM-Test mit System Console (P3, Schritt 1).

Frage: Welche Adressen sieht das FPGA über F2SDRAM — physische HPS-Adressen
(DDR ab 0x8000_0000)? Und sind die Zugriffe kohärent mit den CPU-Caches?

Ablauf (als root, sonst liefert /proc/self/pagemap keine Seitennummern):
    sudo python3 f2sdram_probe.py          Erkennen + einfacher Test (s. u.)
    sudo python3 f2sdram_probe.py --spin   strenger Kohärenztest (siehe spin())
1. Holt 16 Speicherseiten, nagelt sie fest (mlock: der Kernel verschiebt
   oder lagert sie nicht aus) und füllt jede mit einem Muster.
2. Ermittelt die physischen Adressen und gibt sie aus.
3. Verdrängt die Muster aus den CPU-Caches (großen Puffer durchlaufen), damit
   sie sicher im DDR stehen — F2SDRAM liest am Cache vorbei (AxCACHE=2).
4. Wartet: In System Console die angezeigten Adressen lesen (Erwartung steht
   dabei) und an EINE angegebene Adresse schreiben.
5. Liest dieselbe Stelle zweimal: sofort (aus dem Cache?) und nach erneutem
   Verdrängen (aus dem DDR). So sieht man, ob ein FPGA-Schreibzugriff ohne
   Cache-Pflege bei der CPU ankommt.

Analogie: Wir legen einen Zettel mit bekannter Nummer in ein Schließfach,
nennen dem FPGA die Fachnummer und schauen, ob es denselben Zettel findet.
Nur diese Seiten gehören uns — System Console darf nirgends sonst schreiben.
"""
import ctypes
import mmap
import os
import struct
import sys
import time

PAGES = 16
PAGE = os.sysconf("SC_PAGE_SIZE")
MAGIC = 0x52250000          # "R%" + Seitennummer im unteren Halbwort
DIRTY = 0xD1D1D1D1          # nur im Cache: unterscheidet kohärente Master
EVICT = 64 << 20            # 64 MB durchlaufen > L1/L2/L3 der A76/A55


def phys_addr(virt: int) -> int:
    with open("/proc/self/pagemap", "rb") as f:
        f.seek((virt // PAGE) * 8)
        entry = struct.unpack("<Q", f.read(8))[0]
    if not entry >> 63 & 1:
        sys.exit("Seite nicht im Speicher")
    pfn = entry & ((1 << 55) - 1)
    if pfn == 0:
        sys.exit("Seitennummer 0 — bitte mit sudo starten")
    return pfn * PAGE + virt % PAGE


def evict(buf: mmap.mmap) -> None:
    # Jede Cache-Zeile (64 Byte) einmal beschreiben: verdrängt alles andere.
    for off in range(0, len(buf), 64):
        buf[off] = (buf[off] + 1) & 0xFF


def word(m: mmap.mmap, off: int) -> int:
    return struct.unpack_from("<I", m, off)[0]


def spin(m: mmap.mmap, phys0: int, scratch: mmap.mmap) -> None:
    """Strenger Kohärenztest: zwei Stellen ununterbrochen lesen, während
    System Console dorthin schreibt. Die Cache-Zeilen bleiben dabei sicher im
    L1 des einen Kerns — ohne Kohärenz sähe die CPU den neuen Wert nie."""
    os.sched_setaffinity(0, {3})          # immer derselbe Kern (A76), gleicher L1
    offs = (0x100, 0x140)                 # zwei verschiedene 64-Byte-Zeilen
    vals = {0x100: 0xCAFE0001, 0x140: 0xCAFE0002}
    print("Strenger Test: das Skript liest jetzt 180 s lang ohne Pause.")
    print("In System Console nacheinander (beliebig langsam):")
    print(f"  f2s_close; f2s_open 1; f2s_write 0x{phys0 + 0x100:X} 0x{vals[0x100]:08X}")
    print(f"  f2s_close; f2s_open 2; f2s_write 0x{phys0 + 0x140:X} 0x{vals[0x140]:08X}")
    before = {o: word(m, o) for o in offs}
    seen = {}
    t0 = time.monotonic()
    while len(seen) < len(offs) and time.monotonic() - t0 < 180:
        for o in offs:
            if o not in seen and word(m, o) != before[o]:
                seen[o] = time.monotonic() - t0
                print(f"  +{seen[o]:6.1f} s: 0x{phys0 + o:X} = 0x{word(m, o):08X} — im Lauf gesehen")
    evict(scratch)
    for o in offs:
        v = word(m, o)
        if o in seen:
            verdict = "kohärent (trotz heißer Cache-Zeile sofort gesehen)"
        elif v == vals[o]:
            verdict = "NICHT kohärent (erst nach Verdrängen sichtbar)"
        else:
            verdict = "nicht angekommen (0x%08X)" % v
        print(f"  0x{phys0 + o:X} (phy_{1 if o == 0x100 else 2}): {verdict}")


def main() -> int:
    libc = ctypes.CDLL(None, use_errno=True)
    m = mmap.mmap(-1, PAGES * PAGE)
    base = ctypes.addressof(ctypes.c_char.from_buffer(m))
    if libc.mlock(ctypes.c_void_p(base), ctypes.c_size_t(PAGES * PAGE)):
        sys.exit(f"mlock: {os.strerror(ctypes.get_errno())}")

    for p in range(PAGES):
        for w in range(PAGE // 4):
            struct.pack_into("<I", m, p * PAGE + w * 4, MAGIC | p if w == 0 else (p << 16) | w)

    phys = [phys_addr(base + p * PAGE) for p in range(PAGES)]
    scratch = mmap.mmap(-1, EVICT)
    evict(scratch)
    # Erkennungsmerkmal: Seite 1, Wort 2 frisch beschreiben — der neue Wert
    # steht danach (vorerst) nur im CPU-Cache, im DDR noch der alte.
    # Ein kohärenter Master (F2H, hps_m) liest den neuen, F2SDRAM den alten.
    old_dirty = word(m, PAGE + 8)
    struct.pack_into("<I", m, PAGE + 8, DIRTY)

    print(f"{PAGES} Seiten à {PAGE} Byte, festgenagelt. Physische Adressen:")
    for p, a in enumerate(phys):
        print(f"  Seite {p:2d}: 0x{a:09X}   erwartet: Wort 0 = 0x{MAGIC | p:08X}, "
              f"Wort 1 = 0x{(p << 16) | 1:08X}")
    test = phys[0] + 0x100
    if "--spin" in sys.argv:
        spin(m, phys[0], scratch)
        return 0
    print()
    print("Welcher Master ist welcher? (liest nur, mit allen drei Mastern):")
    print(f"  f2s_scan 0x{phys[1]:X} 3")
    print(f"  Wort 0/1 = 0x{MAGIC | 1:08X} 0x{(1 << 16) | 1:08X} -> Master sieht physische Adressen")
    print(f"  Wort 2 = 0x{DIRTY:08X} -> kohärent (F2H, hps_m); "
          f"0x{old_dirty:08X} -> am Cache vorbei (F2SDRAM)")
    print()
    print("Dann den F2SDRAM-Master belegen (f2s_open <Nummer>) und:")
    print(f"  f2s_read 0x{phys[0]:X} 2         ;# Seite 0 lesen")
    print(f"  f2s_read 0x{phys[PAGES - 1]:X} 2         ;# Seite {PAGES - 1} lesen")
    print(f"  f2s_write 0x{test:X} 0xCAFE0001  ;# NUR an diese Adresse schreiben")
    print(f"Vorher steht dort 0x{word(m, 0x100):08X}.")
    input("Enter, wenn gelesen und geschrieben ... ")

    now = word(m, 0x100)
    evict(scratch)
    later = word(m, 0x100)
    print(f"CPU liest 0x{test:X}: sofort 0x{now:08X}, nach Verdrängen 0x{later:08X}")
    if now == 0xCAFE0001:
        print("  -> sofort sichtbar: FPGA-Schreiben kommt ohne Cache-Pflege an (kohärent)")
    elif later == 0xCAFE0001:
        print("  -> erst nach Verdrängen sichtbar: nicht kohärent (Cache-Pflege bzw. "
              "nicht cachebare Abbildung nötig)")
    else:
        print("  -> nicht angekommen: andere Adressabbildung? Lesewerte aus System Console prüfen")
    return 0


if __name__ == "__main__":
    sys.exit(main())
