# SPDX-License-Identifier: GPL-3.0-or-later
"""Holt MiSTers C64-Core (C64_MiSTer) in festem Stand — ohne ROMs.

Aufruf (aus dem Projektverzeichnis Retro25, braucht git):
    python tools/fetch_c64.py

Quelle: https://github.com/MiSTer-devel/C64_MiSTer, Commit COMMIT.
Ziel (unverändert, nicht im Repository; Herkunft in README.retro25.md):
    cores/c64/vendor/   c64.sv, files.qip, C64.qsf, README.md, rtl/
Weggelassen:
  - ROM-Abbilder (urheberrechtlich geschützt): rtl/roms/ (C64-BASIC/KERNAL,
    Zeichensätze), rtl/iec_drive/*.mif (1541-/1581-DOS) — der Bau erzeugt
    sie lokal aus roms/ (P4 Schritt 3)
  - Cyclone-V-PLL: rtl/pll/, rtl/pll.v, rtl/pll.qip (Ersatz in cores/c64/ip/)
  - rtl/opl3/fw/ (Quelltext und Werkzeuge der OPL3-Firmware samt .exe; das
    fertige Abbild opl3prg.mem bleibt)
  - releases/ (fertige .rbf und ROM-Dateien), sys/ (kommt aus sys/vendor/mister
    bzw. sys/de25), C64_Q13.*, *.srf, clean.bat, keymap.gif
Eigene Anpassungen nie dort, sondern in cores/c64/ (Kopie + .patch).
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "https://github.com/MiSTer-devel/C64_MiSTer.git"
COMMIT = "fe6dfe53c99122e5a088691f2d358d6caba61de1"   # 2026-09-06
DST = ROOT / "cores" / "c64" / "vendor"
FILES = ["c64.sv", "files.qip", "C64.qsf", "README.md"]


def skip(rel: Path) -> bool:
    """True für Dateien unter rtl/, die nicht übernommen werden."""
    parts = rel.parts
    if parts[0] in ("roms", "pll") or rel.name in ("pll.v", "pll.qip"):
        return True
    if parts[0] == "iec_drive" and rel.suffix == ".mif":
        return True
    if parts[:2] == ("opl3", "fw"):
        return True
    return False


README = """# C64_MiSTer (unverändert, ohne ROMs)

Herkunft: {repo}, Commit `{commit}`.
Geholt mit `python tools/fetch_c64.py` — hier nichts von Hand ändern.

Weggelassen:

- **ROM-Abbilder** (urheberrechtlich geschützt): `rtl/roms/*.mif` (BASIC und
  KERNAL in den Varianten Standard, C64GS, DolphinDOS, japanisch; Zeichensätze)
  und `rtl/iec_drive/*.mif` (1541-DOS, DolphinDOS-1541, 1581-DOS). Der Bau
  erzeugt die nötigen Dateien lokal aus `roms/` (siehe `roms/README.md`).
- Cyclone-V-PLL `rtl/pll/`, `rtl/pll.v`, `rtl/pll.qip` (Ersatz in
  `cores/c64/ip/`).
- `rtl/opl3/fw/` (Quelltext und Werkzeuge der OPL3-Firmware, darunter eine
  .exe); das fertige Abbild `rtl/opl3/opl3prg.mem` ist enthalten.
- `releases/`, `sys/` (kommt aus `sys/vendor/mister` bzw. `sys/de25`),
  `C64_Q13.*`, `*.srf`, `clean.bat`, `keymap.gif`.

Lizenz: `c64.sv` und weitere Dateien GPL-2.0-or-later (Dateikopf, Copyright
Sorgelig u. a.), `rtl/opl3/NextZ80*` LGPL, `iecdrv_via6522.vhd` GPL. Etwa 40
Dateien haben keinen Lizenzvermerk, darunter der FPGA64-Kern von Peter
Wendrich (VIC-II, Buslogik) — vor einer Veröffentlichung klären. Retro25
insgesamt: GPL-3.0-or-later.
"""


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "c64"
        subprocess.run(["git", "clone", "-q", "--filter=blob:none", "--no-checkout", REPO, str(src)],
                       check=True)
        subprocess.run(["git", "-C", str(src), "checkout", "-q", COMMIT], check=True)
        if DST.exists():
            shutil.rmtree(DST)
        DST.mkdir(parents=True)
        for name in FILES:
            shutil.copy2(src / name, DST / name)
            print(f"{name:12s} -> {(DST / name).relative_to(ROOT)}")
        n = 0
        for p in sorted((src / "rtl").rglob("*")):
            rel = p.relative_to(src / "rtl")
            if p.is_dir() or skip(rel):
                continue
            out = DST / "rtl" / rel
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, out)
            n += 1
        print(f"rtl/: {n} Dateien -> {(DST / 'rtl').relative_to(ROOT)}")
    (DST / "README.retro25.md").write_text(README.format(repo=REPO, commit=COMMIT), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
