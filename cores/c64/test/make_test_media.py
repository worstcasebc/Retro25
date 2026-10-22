# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt Testdateien für den C64-Core: BASIC-Testprogramm, Diskette, MGL.

Aufruf (aus dem Projektverzeichnis Retro25):
    python cores/c64/test/make_test_media.py [ZIELORDNER [PFAD_AM_BOARD]]

Schreibt (Vorgabe: cores/c64/test/out/, von git ignoriert):
  retro25test.prg  BASIC-Programm (startet nach dem Laden selbst, "Reset & Run
                   PRG"): prüft den SID (Rauschgenerator von Stimme 3 über
                   $D41B), liest die Datei TEST von der Diskette, schreibt eine
                   neue Datei und liest sie zurück; zeigt den Fehlerkanal.
  retro25test.d64  leere Diskette "RETRO25 TEST" mit der SEQ-Datei TEST
  retro25test.mgl  lädt den C64, legt die Diskette in Laufwerk 8 ein und
                   startet das Programm — auf dem Board:
                   echo "load_core /media/fat/games/C64/retro25test.mgl" > /dev/MiSTer_cmd
  joytest.prg/.mgl zeigt laufend PEEK(56320) (Port 2) und PEEK(56321) (Port 1);
                   127/255 = nichts gedrückt, Bits 0–4 = hoch, runter, links,
                   rechts, Feuer (aktiv low). Achtung: Port 1 zeigt auch
                   Tasten der Tastaturmatrix-Spalte 7 (1, 2, CTRL, SPACE …).
  crttest8k/16k.crt/.mgl  Testmodul (Typ 0, 8 KB ROML bzw. 16 KB ROML+ROMH):
                   prüft das Modul-ROM ab $8100 gegen ein Muster; Rand grün =
                   "MODUL-ROM OK", rot = "MODUL-ROM FEHLER".
  crttestmd.crt/.mgl  Testmodul Magic Desk (Typ 19, 8 Blöcke à 8 KB): schaltet über $DE00 alle Blöcke durch und
                   prüft je ein eigenes Muster; Ausgabe "BANK n OK" je Block.
  tapetest.tap/.mgl, tapeload.prg  Kassette (TAP v1, CBM-Format) mit einem
                   Programm, das 4 KB Muster ($1000-$1FFF) prüft ("TAPE-DATEN
                   OK", Rand grün). Die MGL startet tapeload.prg ("10 LOAD" —
                   lädt und startet das Bandprogramm) und legt dann das Band ein;
                   von Hand: Shift+Esc (= LOAD/RUN). Laden dauert ca. 1,5 min.
Die Dateien gehören nach PFAD_AM_BOARD (Vorgabe /media/fat/games/C64); die MGL
nennt sie mit diesem absoluten Pfad.
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BOARD_DIR = "/media/fat/games/C64"

# ---------------------------------------------------------------- BASIC
# C64-Token 0x80..0xCB in Tabellenreihenfolge (der Tokenizer des C64 nimmt
# den ersten Treffer, deshalb steht INPUT# vor INPUT, PRINT# vor PRINT)
KEYWORDS = ["END", "FOR", "NEXT", "DATA", "INPUT#", "INPUT", "DIM", "READ", "LET", "GOTO", "RUN", "IF",
            "RESTORE", "GOSUB", "RETURN", "REM", "STOP", "ON", "WAIT", "LOAD", "SAVE", "VERIFY", "DEF",
            "POKE", "PRINT#", "PRINT", "CONT", "LIST", "CLR", "CMD", "SYS", "OPEN", "CLOSE", "GET", "NEW",
            "TAB(", "TO", "FN", "SPC(", "THEN", "NOT", "STEP", "+", "-", "*", "/", "^", "AND", "OR", ">",
            "=", "<", "SGN", "INT", "ABS", "USR", "FRE", "POS", "SQR", "RND", "LOG", "EXP", "COS", "SIN",
            "TAN", "ATN", "PEEK", "LEN", "STR$", "VAL", "ASC", "CHR$", "LEFT$", "RIGHT$", "MID$", "GO"]

PROGRAM = [
    (10, 'PRINT CHR$(147);"RETRO25 C64-TEST"'),
    (20, 'POKE 54287,255:POKE 54290,128'),                 # Stimme 3: Frequenz hoch, Rauschen
    (30, 'S=0:B=-1:FOR I=1 TO 50:A=PEEK(54299):IF A<>B THEN S=S+1'),
    (40, 'B=A:NEXT:PRINT"SID OSC3 WECHSEL";S;"VON 50"'),
    (50, 'OPEN 15,8,15:OPEN 2,8,2,"TEST,S,R":INPUT#2,A$:CLOSE 2:PRINT"GELESEN: ";A$'),
    (60, 'INPUT#15,E,E$:PRINT"STATUS";E;E$'),
    (70, 'OPEN 3,8,3,"@0:NEU,S,W":PRINT#3,"GESCHRIEBEN AM DE25":CLOSE 3'),
    (80, 'INPUT#15,E,E$:PRINT"STATUS";E;E$'),
    (90, 'OPEN 4,8,4,"NEU,S,R":INPUT#4,B$:CLOSE 4:PRINT"ZURUECK: ";B$'),
    (100, 'INPUT#15,E,E$:PRINT"STATUS";E;E$:CLOSE 15'),
    (110, 'PRINT"FERTIG"'),
]

JOYTEST = [
    (10, 'PRINT CHR$(147);"JOYSTICK-TEST: PORT 2 ($DC00)  PORT 1 ($DC01)"'),
    (20, 'PRINT"127/255 = NICHTS GEDRUECKT"'),
    (30, 'A=PEEK(56320):B=PEEK(56321):PRINT CHR$(19);:PRINT:PRINT:PRINT:PRINT"PORT2:";A;"  PORT1:";B;"   "'),
    (40, 'GOTO 30'),
]


def tokenize(text: str) -> bytes:
    out = bytearray()
    i = 0
    in_str = False
    while i < len(text):
        c = text[i]
        if c == '"':
            in_str = not in_str
            out.append(ord(c))
            i += 1
            continue
        if not in_str:
            for n, kw in enumerate(KEYWORDS):
                if text.startswith(kw, i):
                    out.append(0x80 + n)
                    i += len(kw)
                    break
            else:
                if c != " ":                  # Leerzeichen außerhalb von Texten weglassen
                    out.append(ord(c))
                i += 1
            continue
        out.append(ord(c))
        i += 1
    return bytes(out)


def make_prg(program) -> bytes:
    addr = 0x0801
    body = bytearray()
    for num, text in program:
        line = num.to_bytes(2, "little") + tokenize(text) + b"\x00"
        nxt = addr + 2 + len(line)
        body += nxt.to_bytes(2, "little") + line
        addr = nxt
    body += b"\x00\x00"
    return (0x0801).to_bytes(2, "little") + bytes(body)


# ---------------------------------------------------------------- D64
def sectors(track: int) -> int:
    return 21 if track <= 17 else 19 if track <= 24 else 18 if track <= 30 else 17


def offset(track: int, sector: int) -> int:
    return (sum(sectors(t) for t in range(1, track)) + sector) * 256


def petscii_name(name: str, length: int = 16) -> bytes:
    return name.encode("ascii")[:length].ljust(length, b"\xa0")


def make_d64() -> bytes:
    img = bytearray(683 * 256)
    used = {(18, 0), (18, 1), (17, 0)}
    # BAM (18/0)
    bam = bytearray(256)
    bam[0:4] = bytes([18, 1, 0x41, 0])
    for t in range(1, 36):
        free = [(s not in [x[1] for x in used if x[0] == t]) for s in range(sectors(t))]
        bits = sum(1 << s for s, f in enumerate(free) if f)
        bam[4 * t:4 * t + 4] = bytes([sum(free), bits & 0xFF, (bits >> 8) & 0xFF, (bits >> 16) & 0xFF])
    bam[0x90:0xA0] = petscii_name("RETRO25 TEST")
    bam[0xA0:0xAB] = b"\xa0\xa0R5\xa02A\xa0\xa0\xa0\xa0"
    img[offset(18, 0):offset(18, 0) + 256] = bam
    # Verzeichnis (18/1): eine SEQ-Datei TEST auf 17/0, 1 Block
    d = bytearray(256)
    d[0:2] = bytes([0, 0xFF])
    d[2] = 0x81                                  # SEQ, geschlossen
    d[3:5] = bytes([17, 0])
    d[5:21] = petscii_name("TEST")
    d[30:32] = (1).to_bytes(2, "little")
    img[offset(18, 1):offset(18, 1) + 256] = d
    # Daten (17/0)
    data = b"HALLO VOM DE25-NANO\r"
    s = bytearray(256)
    s[0] = 0                                     # letzter Block
    s[1] = 1 + len(data)                         # letztes benutztes Byte
    s[2:2 + len(data)] = data
    img[offset(17, 0):offset(17, 0) + 256] = s
    return bytes(img)


# ---------------------------------------------------------------- CRT
# Testmodul: Startcode ab $8000 (Kennung CBM80), danach ab $8100 ein Muster
# (Byte = Adresse low XOR Adresse high), das der Code selbst nachprüft. So
# fallen fehlende, verschobene oder vertauschte Bytes/Bänke auf.
CHROUT = 0xFFD2


def assemble(org: int, items) -> bytes:
    """Mini-Assembler: Bytes, ("abs", label[, offset]), ("rel", label), ("lo"/"hi", label), Label-Strings."""
    labels, pc = {}, org
    for it in items:                             # 1. Durchlauf: Adressen der Labels
        if isinstance(it, str):
            labels[it] = pc
        elif isinstance(it, tuple):
            pc += 2 if it[0] == "abs" else 1
        else:
            pc += len(it)
    out = bytearray()
    for it in items:                             # 2. Durchlauf: Code erzeugen
        if isinstance(it, str):
            continue
        if isinstance(it, tuple):
            kind, lab = it[:2]
            a = labels[lab] + (it[2] if len(it) > 2 else 0)
            if kind == "abs":
                out += a.to_bytes(2, "little")
            elif kind == "lo":
                out.append(a & 0xFF)
            elif kind == "hi":
                out.append(a >> 8)
            else:                                # relativer Sprung
                d = a - (org + len(out) + 1)
                assert -128 <= d <= 127, lab
                out.append(d & 0xFF)
        else:
            out += it
    return bytes(out)


def make_cart_rom(size: int) -> bytes:
    end_hi = (0x8000 + size) >> 8                # erste Seite hinter dem ROM
    kb = size // 1024

    def printmsg(lab):
        return [b"\xa9", ("lo", lab), b"\x85\x22", b"\xa9", ("hi", lab), b"\x85\x23", b"\x20", ("abs", "print")]

    code = [
        ("abs", "cold"), ("abs", "cold"), b"\xc3\xc2\xcd\x38\x30",   # Vektoren + CBM80
        "cold",
        b"\x78\xa2\xff\x9a\xd8",                 # SEI, LDX #$FF, TXS, CLD
        b"\x20\xa3\xfd", b"\x20\x50\xfd",        # JSR IOINIT, JSR RAMTAS
        b"\x20\x15\xfd", b"\x20\x5b\xff",        # JSR RESTOR, JSR CINT
        b"\x58",                                 # CLI
        *printmsg("m_title"),
        b"\xa9\x00\x85\xfb\x85\xfd",             # LDA #0, STA $FB, STA $FD (Fehlerflag)
        b"\xa9\x81\x85\xfc\xa0\x00",             # LDA #$81, STA $FC, LDY #0
        "loop",
        b"\x98\x45\xfc\xd1\xfb",                 # TYA, EOR $FC, CMP ($FB),Y
        b"\xf0", ("rel", "same"),
        b"\xa9\x01\x85\xfd",                     # Fehler: LDA #1, STA $FD
        "same",
        b"\xc8\xd0", ("rel", "loop"),            # INY, BNE loop
        b"\xe6\xfc\xa5\xfc\xc9", bytes([end_hi]),  # INC $FC, LDA $FC, CMP #end_hi
        b"\xd0", ("rel", "loop"),
        b"\xa5\xfd\xd0", ("rel", "bad"),         # LDA $FD, BNE bad
        *printmsg("m_ok"),
        b"\xa9\x05\x8d\x20\xd0",                 # Rand grün
        b"\x4c", ("abs", "halt"),
        "bad",
        *printmsg("m_bad"),
        b"\xa9\x02\x8d\x20\xd0",                 # Rand rot
        "halt",
        b"\x4c", ("abs", "halt"),
        "print",                                 # Text ab ($22) bis 0 ausgeben
        b"\xa0\x00",
        "ploop",
        b"\xb1\x22\xf0", ("rel", "pend"),
        b"\x20", CHROUT.to_bytes(2, "little"),
        b"\xc8\xd0", ("rel", "ploop"),
        "pend",
        b"\x60",
        "m_title", b"\x93RETRO25 CRT-TEST %dK\r" % kb + b"PRUEFE $8100-$%04X ...\r" % (0x8000 + size - 1) + b"\x00",
        "m_ok", b"MODUL-ROM OK\r\x00",
        "m_bad", b"MODUL-ROM FEHLER\r\x00",
    ]
    head = assemble(0x8000, code)
    assert len(head) <= 0x100, len(head)
    rom = bytearray(head.ljust(0x100, b"\x00"))
    for a in range(0x8100, 0x8000 + size):
        rom.append((a & 0xFF) ^ (a >> 8))
    return bytes(rom)


def make_crt(size: int) -> bytes:
    """CRT-Datei Typ 0 (normales Modul), ein CHIP-Paket ab $8000."""
    exrom, game = (0, 1) if size == 0x2000 else (0, 0)
    hdr = (b"C64 CARTRIDGE   " + (0x40).to_bytes(4, "big") + b"\x01\x00" + (0).to_bytes(2, "big")
           + bytes([exrom, game]) + bytes(6) + b"RETRO25 TEST %dK" % (size // 1024)).ljust(0x40, b"\x00")
    chip = (b"CHIP" + (0x10 + size).to_bytes(4, "big") + (0).to_bytes(2, "big") + (0).to_bytes(2, "big")
            + (0x8000).to_bytes(2, "big") + size.to_bytes(2, "big"))
    return hdr + chip + make_cart_rom(size)


# Magic Desk (CRT-Typ 19): Schreiben nach $DE00 blendet einen von bis zu 128
# 8-KB-Blöcken bei $8000 ein. Der Prüfcode läuft aus dem RAM ($C000), weil er
# beim Umschalten sonst unter sich selbst weggeblendet würde.
MD_BANKS = 8


def md_key(bank: int) -> int:
    return (bank << 5 | bank) & 0xFF


def make_md_ram_code(first_hi: int) -> bytes:
    def printmsg(lab):
        return [b"\xa9", ("lo", lab), b"\x85\x22", b"\xa9", ("hi", lab), b"\x85\x23", b"\x20", ("abs", "print")]

    code = [
        b"\xa9\x00\x85\x04",                     # LDA #0, STA $04 (Fehler gesamt)
        b"\xa9", bytes([MD_BANKS - 1]), b"\x85\x02",  # LDA #n-1, STA $02 (Block)
        "bank",
        b"\xa5\x02\x8d\x00\xde",                 # LDA $02, STA $DE00 (Bit 7 = 0: Modul an)
        *printmsg("m_bank"),
        b"\xa5\x02\x09\x30\x20", CHROUT.to_bytes(2, "little"),  # Ziffer ausgeben
        b"\xa5\x02\x0a\x0a\x0a\x0a\x0a\x05\x02\x85\x03",       # $03 = Block*$21
        b"\xa9\x00\x85\xfb\x85\xfd\xa0\x00",     # Zeiger low, Fehlerflag, Y = 0
        b"\xa9\x80\x85\xfc",                     # Zeiger high = $80
        b"\xa5\x02\xd0", ("rel", "loop"),        # Block 0: Code-Bereich überspringen
        b"\xa9", bytes([first_hi]), b"\x85\xfc",
        "loop",
        b"\x98\x45\xfc\x45\x03\xd1\xfb",         # TYA, EOR $FC, EOR $03, CMP ($FB),Y
        b"\xf0", ("rel", "same"),
        b"\xa9\x01\x85\xfd\x85\x04",
        "same",
        b"\xc8\xd0", ("rel", "loop"),
        b"\xe6\xfc\xa5\xfc\xc9\xa0\xd0", ("rel", "loop"),     # bis $9FFF
        b"\xa5\xfd\xd0", ("rel", "bbad"),
        *printmsg("m_ok"),
        b"\x4c", ("abs", "next"),
        "bbad",
        *printmsg("m_bad"),
        "next",
        b"\xc6\x02\x10", ("rel", "bank"),        # DEC $02, BPL bank
        b"\xa5\x04\xd0", ("rel", "fbad"),
        *printmsg("m_all"),
        b"\xa9\x05\x8d\x20\xd0\x4c", ("abs", "halt"),
        "fbad",
        *printmsg("m_fail"),
        b"\xa9\x02\x8d\x20\xd0",
        "halt",
        b"\x4c", ("abs", "halt"),
        "print",
        b"\xa0\x00",
        "ploop",
        b"\xb1\x22\xf0", ("rel", "pend"),
        b"\x20", CHROUT.to_bytes(2, "little"),
        b"\xc8\xd0", ("rel", "ploop"),
        "pend",
        b"\x60",
        "m_bank", b"BANK \x00",
        "m_ok", b" OK\r\x00",
        "m_bad", b" FEHLER\r\x00",
        "m_all", b"ALLE BAENKE OK\r\x00",
        "m_fail", b"MODUL-ROM FEHLER\r\x00",
    ]
    return assemble(0xC000, code)


def make_md_banks() -> list:
    first_hi = 0x82                              # Block 0: Code in $8000-$81FF
    ram = make_md_ram_code(first_hi)
    assert len(ram) < 0x100, len(ram)
    boot = [
        ("abs", "cold"), ("abs", "cold"), b"\xc3\xc2\xcd\x38\x30",
        "cold",
        b"\x78\xa2\xff\x9a\xd8",
        b"\x20\xa3\xfd", b"\x20\x50\xfd", b"\x20\x15\xfd", b"\x20\x5b\xff", b"\x58",
        b"\xa2\x00",                             # Titel ausgeben
        "t",
        b"\xbd", ("abs", "title"), b"\xf0", ("rel", "copy"),
        b"\x20", CHROUT.to_bytes(2, "little"), b"\xe8\xd0", ("rel", "t"),
        "copy",
        b"\xa2\x00",                             # Prüfcode nach $C000 kopieren
        "c",
        b"\xbd", ("abs", "ram"), b"\x9d\x00\xc0\xe8\xe0", bytes([len(ram)]), b"\xd0", ("rel", "c"),
        b"\x4c\x00\xc0",
        "title", b"\x93RETRO25 CRT-TEST MAGIC DESK %dK\r\x00" % (MD_BANKS * 8),
        "ram", ram,
    ]
    head = assemble(0x8000, boot)
    assert len(head) <= (first_hi - 0x80) << 8, len(head)
    banks = []
    for b in range(MD_BANKS):
        rom = bytearray(0x2000)
        for a in range(0x8000, 0xA000):
            rom[a - 0x8000] = (a & 0xFF) ^ (a >> 8) ^ md_key(b)
        if b == 0:
            rom[:(first_hi - 0x80) << 8] = head.ljust((first_hi - 0x80) << 8, b"\x00")
        banks.append(bytes(rom))
    return banks


def make_crt_md() -> bytes:
    """CRT-Datei Typ 19 (Magic Desk), CHIP-Pakete aufsteigend.

    MiSTers cartridge.v legt die Blöcke in Ladereihenfolge ab und adressiert sie
    direkt über die Blocknummer (die Tabelle lobanks nutzt nur EasyFlash) —
    Pakete in anderer Reihenfolge (z. B. rückwärts) funktionieren dort nicht.
    """
    hdr = (b"C64 CARTRIDGE   " + (0x40).to_bytes(4, "big") + b"\x01\x00" + (19).to_bytes(2, "big")
           + bytes([0, 1]) + bytes(6) + b"RETRO25 TEST MAGIC DESK").ljust(0x40, b"\x00")
    out = bytearray(hdr)
    for b, rom in enumerate(make_md_banks()):
        out += (b"CHIP" + (0x2010).to_bytes(4, "big") + (0).to_bytes(2, "big") + b.to_bytes(2, "big")
                + (0x8000).to_bytes(2, "big") + (0x2000).to_bytes(2, "big") + rom)
    return bytes(out)


# ---------------------------------------------------------------- TAP
# Kassette im CBM-Format: Impulslängen in 8-Takt-Einheiten (TAP-Datei).
# Bit 0 = kurz+mittel, Bit 1 = mittel+kurz; jedes Byte beginnt mit lang+mittel
# und endet mit einem Paritätsbit (ungerade); lang+kurz = Blockende.
# Kopf- und Datenblock stehen je zweimal auf dem Band (Countdown $89..$81 bzw.
# $09..$01), mit XOR-Prüfsumme — das KERNAL prüft sie beim Laden.
TAP_S, TAP_M, TAP_L = 0x30, 0x42, 0x56
TAP_DATA = 0x1000                                # Testmuster $1000-$1FFF


def tap_byte(b: int) -> list:
    p = [TAP_L, TAP_M]
    for i in range(8):
        p += [TAP_M, TAP_S] if b >> i & 1 else [TAP_S, TAP_M]
    p += [TAP_M, TAP_S] if bin(b).count("1") % 2 == 0 else [TAP_S, TAP_M]
    return p


def tap_block(data: bytes, leader: int) -> list:
    chk = 0
    for b in data:
        chk ^= b
    p = [TAP_S] * leader
    for first, gap in ((0x89, 0x4F), (0x09, 0x4E)):   # zweite Kopie danach, dann Nachlauf
        for c in range(first, first - 9, -1):
            p += tap_byte(c)
        for b in data:
            p += tap_byte(b)
        p += tap_byte(chk) + [TAP_L, TAP_S] + [TAP_S] * gap
    return p


def make_tap_prg() -> bytes:
    """BASIC-Zeile 10 SYS2061, Prüfcode, Muster ab $1000 (lo ^ hi ^ $5A)."""
    def printmsg(lab):
        return [b"\xa9", ("lo", lab), b"\x85\x22", b"\xa9", ("hi", lab), b"\x85\x23", b"\x20", ("abs", "print")]

    stub = make_prg([(10, "SYS2061")])[2:]      # ohne Ladeadresse, endet mit 00 00
    org = 0x0801 + len(stub)
    assert org == 2061
    code = [
        *printmsg("m_title"),
        b"\xa9\x00\x85\xfd\x85\xfb\xa9", bytes([TAP_DATA >> 8]), b"\x85\xfc\xa0\x00",
        "loop",
        b"\x98\x45\xfc\x49\x5a\xd1\xfb",         # TYA, EOR $FC, EOR #$5A, CMP ($FB),Y
        b"\xf0", ("rel", "same"),
        b"\xa9\x01\x85\xfd",
        "same",
        b"\xc8\xd0", ("rel", "loop"),
        b"\xe6\xfc\xa5\xfc\xc9", bytes([(TAP_DATA >> 8) + 0x10]), b"\xd0", ("rel", "loop"),
        b"\xa5\xfd\xd0", ("rel", "bad"),
        *printmsg("m_ok"),
        b"\xa9\x05\x8d\x20\xd0\x60",             # Rand grün, RTS
        "bad",
        *printmsg("m_bad"),
        b"\xa9\x02\x8d\x20\xd0\x60",             # Rand rot, RTS
        "print",
        b"\xa0\x00",
        "ploop",
        b"\xb1\x22\xf0", ("rel", "pend"),
        b"\x20", CHROUT.to_bytes(2, "little"),
        b"\xc8\xd0", ("rel", "ploop"),
        "pend",
        b"\x60",
        "m_title", b"\rRETRO25 TAPE-TEST\rPRUEFE $1000-$1FFF ...\r\x00",
        "m_ok", b"TAPE-DATEN OK\r\x00",
        "m_bad", b"TAPE-DATEN FEHLER\r\x00",
    ]
    body = bytearray(stub + assemble(org, code))
    assert 0x0801 + len(body) <= TAP_DATA
    body = body.ljust(TAP_DATA - 0x0801, b"\x00")
    for a in range(TAP_DATA, TAP_DATA + 0x1000):
        body.append((a & 0xFF) ^ (a >> 8) ^ 0x5A)
    return bytes(body)


def make_tap() -> bytes:
    """TAP Version 1 mit einem Programm 'RETRO25 TAPE' (Typ 1 = BASIC, ab $0801)."""
    prog = make_tap_prg()
    end = 0x0801 + len(prog)
    hdr = (bytes([1]) + (0x0801).to_bytes(2, "little") + end.to_bytes(2, "little")
           + b"RETRO25 TAPE".ljust(16, b" ")).ljust(192, b" ")
    # ~10 s Nachlauf: MiSTers tape_subsystem wirft das Band schon beim letzten
    # Zählschritt (~3 s) aus ("Tape Auto Unload") — ohne Nachlauf fehlt dann
    # das Ende der zweiten Kopie samt Prüfsumme (KERNAL: ST=$20).
    pulses = tap_block(hdr, 0x6A00) + tap_block(prog, 0x1500) + [TAP_S] * 25000
    return b"C64-TAPE-RAW" + bytes([1, 0, 0, 0]) + len(pulses).to_bytes(4, "little") + bytes(pulses)


def make_tap_loader() -> bytes:
    """Lader: lädt das erste Programm vom Band per KERNAL-LOAD (Meldungen an),
    zeigt ST ($90), die Fehlerzähler der zwei Durchgänge ($9E/$9F), die
    Endadresse und die XOR-Summe des geladenen Bereichs und startet das
    Programm (SYS 2061) — bei Ladefehlern trotzdem, für dessen Musterprüfung. Läuft aus $C000, weil das
    Bandprogramm $0801.. überschreibt."""
    def printmsg(lab):
        return [b"\xa9", ("lo", lab), b"\x85\x22", b"\xa9", ("hi", lab), b"\x85\x23", b"\x20", ("abs", "print")]

    def printhex(zp):
        return [b"\xa5", bytes([zp]), b"\x20", ("abs", "hex")]

    main = assemble(0xC000, [
        b"\xa9\x80\x20\x90\xff",                 # SETMSG: Meldungen wie im Direktmodus
        b"\xa9\x01\xa2\x01\xa0\x00\x20\xba\xff",  # SETLFS 1,1,0
        b"\xa9\x00\x20\xbd\xff",                 # SETNAM "" (erstes Programm)
        b"\xa9\x00\xa2\x01\xa0\x08\x20\xd5\xff",  # LOAD nach $0801
        b"\xa9\x00\x2a\x85\x02",                 # Carry -> $02
        b"\x86\x03\x84\x04",                     # Endadresse (X/Y) -> $03/$04
        b"\xa9\x00\x85\x05\x85\xfb\xa9\x08\x85\xfc\xa0\x01",  # XOR ab $0801 bis Ende
        "x",
        b"\xa5\xfc\xc5\x04\xd0\x04\xc4\x03\xf0", ("rel", "xd"),
        b"\xb1\xfb\x45\x05\x85\x05\xc8\xd0", ("rel", "x"),
        b"\xe6\xfc\xd0", ("rel", "x"),
        "xd",
        *printmsg("m_st"), *printhex(0x90),
        *printmsg("m_p1"), *printhex(0x9E),
        *printmsg("m_p2"), *printhex(0x9F),
        *printmsg("m_c"), *printhex(0x02),
        *printmsg("m_e"), *printhex(0x04), *printhex(0x03),
        *printmsg("m_x"), *printhex(0x05),
        b"\xa9\x0d\x20", CHROUT.to_bytes(2, "little"),
        b"\xa5\x02\xd0", ("rel", "fail"),
        b"\xa5\x90\x29\x3c\xd0", ("rel", "fail"),  # ST-Fehlerbits
        b"\x4c\x0d\x08",                         # JMP 2061 (Bandprogramm)
        "fail",                                  # trotzdem starten: Musterprüfung
        *printmsg("m_f"),
        b"\x4c\x0d\x08",
        "hex",                                   # A als zwei Hexziffern
        b"\x48\x4a\x4a\x4a\x4a\x20", ("abs", "nib"), b"\x68\x29\x0f",
        "nib",
        b"\xc9\x0a\x90\x02\x69\x06\x69\x30\x4c", CHROUT.to_bytes(2, "little"),
        "print",
        b"\xa0\x00",
        "ploop",
        b"\xb1\x22\xf0", ("rel", "pend"),
        b"\x20", CHROUT.to_bytes(2, "little"),
        b"\xc8\xd0", ("rel", "ploop"),
        "pend",
        b"\x60",
        "m_st", b"\rST=\x00", "m_p1", b" P1=\x00", "m_p2", b" P2=\x00", "m_c", b" C=\x00",
        "m_e", b"\rENDE=\x00", "m_x", b" XOR=\x00", "m_f", b"LADEFEHLER - STARTE TROTZDEM\x00",
    ])
    assert len(main) <= 0x200
    stub = make_prg([(10, "SYS2061")])[2:]
    copy = assemble(2061, [
        b"\xa2\x00",
        "c",                                     # zwei Seiten nach $C000 kopieren
        b"\xbd", ("abs", "src"), b"\x9d\x00\xc0",
        b"\xbd", ("abs", "src", 0x100), b"\x9d\x00\xc1\xe8\xd0", ("rel", "c"),
        b"\x4c\x00\xc0",
        "src", main,
    ])
    return (0x0801).to_bytes(2, "little") + stub + copy


# Reihenfolge wichtig: Laden einer PRG setzt den C64 zurück, und ein Reset
# wirft das Band aus (tape_subsystem: tap_reset = ~reset_n | ...). Deshalb
# zuerst tapeload.prg (wartet bei PRESS PLAY ON TAPE), dann das Band —
# "Tape Auto Play" drückt PLAY nach dem Einlegen.
MGL_TAP = """<mistergamedescription>
	<rbf>_Retro25/C64</rbf>
	<file delay="2" type="f" index="1" path="{d}/tapeload.prg"/>
	<file delay="3" type="f" index="1" path="{d}/tapetest.tap"/>
</mistergamedescription>
"""

MGL = """<mistergamedescription>
	<rbf>_Retro25/C64</rbf>
	<file delay="1" type="s" index="0" path="{d}/retro25test.d64"/>
	<file delay="2" type="f" index="1" path="{d}/retro25test.prg"/>
</mistergamedescription>
"""

MGL_CRT = """<mistergamedescription>
	<rbf>_Retro25/C64</rbf>
	<file delay="2" type="f" index="1" path="{d}/{n}"/>
</mistergamedescription>
"""

MGL_JOY = """<mistergamedescription>
	<rbf>_Retro25/C64</rbf>
	<file delay="2" type="f" index="1" path="{d}/joytest.prg"/>
</mistergamedescription>
"""


def main() -> int:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "out"
    out.mkdir(parents=True, exist_ok=True)
    (out / "retro25test.prg").write_bytes(make_prg(PROGRAM))
    (out / "joytest.prg").write_bytes(make_prg(JOYTEST))
    (out / "retro25test.d64").write_bytes(make_d64())
    board = sys.argv[2] if len(sys.argv) > 2 else BOARD_DIR
    (out / "retro25test.mgl").write_text(MGL.format(d=board), encoding="ascii", newline="\n")
    (out / "joytest.mgl").write_text(MGL_JOY.format(d=board), encoding="ascii", newline="\n")
    for size in (0x2000, 0x4000):
        name = f"crttest{size // 1024}k"
        (out / f"{name}.crt").write_bytes(make_crt(size))
        (out / f"{name}.mgl").write_text(MGL_CRT.format(d=board, n=f"{name}.crt"), encoding="ascii", newline="\n")
    (out / "crttestmd.crt").write_bytes(make_crt_md())
    (out / "crttestmd.mgl").write_text(MGL_CRT.format(d=board, n="crttestmd.crt"), encoding="ascii", newline="\n")
    (out / "tapetest.tap").write_bytes(make_tap())
    (out / "tapeload.prg").write_bytes(make_tap_loader())
    (out / "tapetest.mgl").write_text(MGL_TAP.format(d=board), encoding="ascii", newline="\n")
    for p in sorted(out.iterdir()):
        print(f"{p.name:18s} {p.stat().st_size:7d} Bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
