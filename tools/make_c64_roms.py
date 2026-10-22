# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt die ROM-Abbilder (.mif) des C64-Cores aus den lokalen ROMs in roms/.

Aufruf (aus dem Projektverzeichnis Retro25, vor dem Bau des C64-Cores):
    python tools/make_c64_roms.py

C64_MiSTer bindet seine ROMs als .mif mit Pfaden relativ zum Quartus-Projekt
ein ("rtl/roms/std_C64.mif" usw.). Die Originale sind urheberrechtlich
geschützt und fehlen in cores/c64/vendor/; dieses Skript schreibt sie nach
cores/c64/quartus/rtl/... — dort sucht Quartus sie, und git ignoriert den
Ordner. Die erzeugte .rbf enthält danach die ROMs: nur für den eigenen
Gebrauch, nicht weitergeben.

Benötigt (Namen wie in roms/README.md): basic-901226-01.bin,
kernal-901227-03.bin, chargen-901225-01.bin, dos1541-325302-01+901229-05.bin.
Das 1541-DOS bekommt denselben kleinen Patch wie bei MiSTer (PATCH_1541).
Varianten, für die es hier keine ROMs gibt (C64GS, japanisch, DolphinDOS,
1581), bekommen den Standardinhalt bzw. Nullen — im OSD wählbar, aber
dann gleich dem Standard bzw. ohne Funktion.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "roms"
OUT = ROOT / "cores" / "c64" / "quartus" / "rtl"


# MiSTers c1541_rom.mif = DOS 325302-01 + 901229-05 mit diesem Patch: Nach der
# Initialisierung (Sprung bei $EE3E) setzt neuer Code bei $FF2F die gemerkte
# Spur ($51) auf $FF (unbekannt) und springt weiter nach $C8C6 — der erste
# Zugriff fährt den Kopf dann sauber an. $FEE6 gleicht die Prüfsumme aus.
PATCH_1541 = {
    0xEE3E: (0xC6, 0x2F), 0xEE3F: (0xC8, 0xFF),          # JMP $C8C6 -> JMP $FF2F
    0xFF2F: (0xAA, 0xA9), 0xFF30: (0xAA, 0xFF),          # LDA #$FF
    0xFF31: (0xAA, 0x85), 0xFF32: (0xAA, 0x51),          # STA $51
    0xFF33: (0xAA, 0x4C), 0xFF34: (0xAA, 0xC6), 0xFF35: (0xAA, 0xC8),   # JMP $C8C6
    0xFEE6: (0x3E, 0xEC),                                 # Prüfsumme
}


def patch_1541(data: bytes) -> bytes:
    d = bytearray(data)
    for addr, (old, new) in PATCH_1541.items():
        if d[addr - 0xC000] != old:
            sys.exit(f"1541-DOS: ${addr:04X} ist {d[addr - 0xC000]:02X}, erwartet {old:02X} (andere ROM-Version?)")
        d[addr - 0xC000] = new
    return bytes(d)


def rom(name: str, size: int) -> bytes:
    p = SRC / name
    if not p.exists():
        sys.exit(f"fehlt: {p} (siehe roms/README.md)")
    data = p.read_bytes()
    if len(data) != size:
        sys.exit(f"{p}: {len(data)} Bytes, erwartet {size}")
    return data


def write_mif(rel: str, data: bytes) -> None:
    out = OUT / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"WIDTH=8;\nDEPTH={len(data)};\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\n\nCONTENT BEGIN\n"]
    for a in range(0, len(data), 16):
        chunk = " ".join(f"{b:02X}" for b in data[a:a + 16])
        lines.append(f"{a:04X}: {chunk};\n")
    lines.append("END;\n")
    out.write_text("".join(lines), encoding="ascii")
    print(f"{rel:28s} {len(data):6d} Bytes")


def write_hex(rel: str, data: bytes) -> None:
    """Hex-Text für $readmemh (ein Byte je Zeile) — die Laufwerks-ROMs lädt
    iecdrv_mem so (Quartus Pro, siehe cores/c64/README.md)."""
    out = OUT / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("".join(f"{b:02X}" + chr(10) for b in data), encoding="ascii")
    print(f"{rel:28s} {len(data):6d} Bytes")


def main() -> int:
    basic = rom("basic-901226-01.bin", 8192)
    kernal = rom("kernal-901227-03.bin", 8192)
    chargen = rom("chargen-901225-01.bin", 4096)
    dos1541 = patch_1541(rom("dos1541-325302-01+901229-05.bin", 16384))

    # Adresse im 16-KB-ROM: cpuAddr(14) & cpuAddr(12..0) -> BASIC ($A000) unten,
    # KERNAL ($E000) oben (fpga64_buslogic.vhd)
    c64 = basic + kernal
    # dol_C64 ist das ladbare ROM ("System ROM: Loadable C64", Vorgabe im OSD)
    for name in ("std_C64", "dol_C64", "std_C64GS", "jap_C64"):
        write_mif(f"roms/{name}.mif", c64)
    for name in ("chargen", "chargenj"):
        write_mif(f"roms/{name}.mif", chargen)

    write_hex("iec_drive/c1541_rom.hex", dos1541)
    # DolphinDOS-1541 (32 KB): ohne Original zweimal das Standard-DOS
    write_hex("iec_drive/c1541_dolphin.hex", dos1541 + dos1541)
    # 1581-DOS (32 KB): ohne Original leer — 1581 funktioniert dann nicht
    write_hex("iec_drive/c1581_rom.hex", bytes(32768))
    return 0


if __name__ == "__main__":
    sys.exit(main())
