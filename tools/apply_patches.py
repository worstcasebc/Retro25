# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt die angepassten Kopien (pro/) aus vendor/ und den .patch-Dateien.

Aufruf (aus dem Projektverzeichnis Retro25, nach den fetch-Skripten):
    python tools/apply_patches.py            alle pro/-Kopien erzeugen
    python tools/apply_patches.py --check    nur prüfen, ob sie aktuell sind

Fremdcode liegt nicht im Repository (Lizenzen, siehe README.md), nur die
Patches. Zu jeder Datei <pro>/<pfad>.patch gehört die Vorlage
<vendor>/<pfad>; das Ergebnis ist <pro>/<pfad>. Paare:
    cores/c64/pro      <- cores/c64/vendor
    cores/menu/pro     <- cores/menu/vendor
    cores/memtest/pro  <- cores/memtest/vendor
    sys/de25/pro       <- sys/vendor/mister
Der z486 hat ein eigenes Skript (cores/z486/make_pro.py, Textersetzungen).

Die Patches werden streng angewendet (Kontextzeilen müssen genau passen, kein
"fuzz") — eine geänderte Vorlage fällt so sofort auf. Zeilenenden (CRLF der
Vorlagen) bleiben erhalten.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAIRS = [
    ("cores/c64/pro", "cores/c64/vendor"),
    ("cores/menu/pro", "cores/menu/vendor"),
    ("cores/memtest/pro", "cores/memtest/vendor"),
    ("sys/de25/pro", "sys/vendor/mister"),
]
HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def apply(src: str, patch: str, name: str) -> str:
    """Wendet einen Unified Diff streng auf src an (Zeilen mit Zeilenende)."""
    old = src.splitlines(keepends=True)
    out = []
    pos = 0                                  # nächste unbenutzte Zeile in old
    lines = patch.splitlines(keepends=True)
    i = 0
    while i < len(lines) and not lines[i].startswith("@@"):
        i += 1                               # Kopf (Beschreibung, ---/+++)
    while i < len(lines):
        m = HUNK.match(lines[i])
        if not m:
            raise SystemExit(f"{name}: unerwartete Zeile im Patch: {lines[i]!r}")
        start = int(m.group(1)) - 1 if m.group(2) != "0" else int(m.group(1))
        out.extend(old[pos:start])
        pos = start
        i += 1
        while i < len(lines) and not lines[i].startswith("@@"):
            ln = lines[i]
            tag, body = ln[:1], ln[1:]
            if tag == "\\":                  # "\ No newline at end of file"
                if out and out[-1].endswith("\n") and lines[i - 1][:1] in "+ ":
                    out[-1] = out[-1].rstrip("\r\n")
                i += 1
                continue
            if tag in (" ", "-"):
                have = old[pos] if pos < len(old) else ""
                if have.rstrip("\r\n") != body.rstrip("\r\n"):
                    raise SystemExit(f"{name}: Patch passt nicht bei Zeile {pos + 1}:\n"
                                     f"  erwartet {body.rstrip()!r}\n  gefunden {have.rstrip()!r}")
                if tag == " ":
                    out.append(have)
                pos += 1
            elif tag == "+":
                eol = "\r\n" if (old and old[0].endswith("\r\n")) else "\n"
                out.append(body.rstrip("\r\n") + (eol if body.endswith("\n") else ""))
            else:
                raise SystemExit(f"{name}: unbekannte Patchzeile {ln!r}")
            i += 1
    out.extend(old[pos:])
    return "".join(out)


def unix(b: bytes) -> bytes:
    """Zeilenenden vereinheitlichen (zum Vergleichen)."""
    return b.replace(b"\r\n", b"\n")


def main() -> int:
    check = "--check" in sys.argv[1:]
    bad = done = 0
    for pro, vendor in PAIRS:
        for p in sorted((ROOT / pro).rglob("*.patch")):
            rel = p.relative_to(ROOT / pro).as_posix()[:-len(".patch")]
            src = ROOT / vendor / rel
            dst = ROOT / pro / rel
            ptext = p.read_bytes().decode("utf-8")
            if not src.exists():
                # Vorlage an anderer Stelle (z. B. C64: pro/sdram.v <- vendor/rtl/sdram.v):
                # Pfad aus dem Patchkopf "--- a/<pfad>"
                m = re.search(r"^--- (?:a/)?(\S+)", ptext, re.M)
                if m and (ROOT / vendor / m.group(1)).exists():
                    src = ROOT / vendor / m.group(1)
                else:
                    # sonst: eindeutiger Dateiname irgendwo unter vendor/
                    # (Menü: pro/sdram.sv <- vendor/rtl/sdram.sv)
                    hits = list((ROOT / vendor).rglob(Path(rel).name))
                    if len(hits) == 1:
                        src = hits[0]
            if not src.exists():
                raise SystemExit(f"Vorlage fehlt: {src.relative_to(ROOT)} (erst die fetch-Skripte laufen lassen)")
            text = src.read_bytes().decode("utf-8")
            result = apply(text, ptext, f"{pro}/{rel}").encode("utf-8")
            if check:
                # Zeilenenden hängen davon ab, wie git die Vorlagen auscheckt
                if not dst.exists() or unix(dst.read_bytes()) != unix(result):
                    print(f"veraltet: {pro}/{rel}")
                    bad += 1
            else:
                dst.parent.mkdir(parents=True, exist_ok=True)
                dst.write_bytes(result)
            done += 1
    print(f"{done} Dateien {'geprüft' if check else 'erzeugt'}" + (f", {bad} weichen ab" if check else ""))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
