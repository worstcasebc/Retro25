# SPDX-License-Identifier: GPL-3.0-or-later
"""Holt MiSTers NES-Core (NES_MiSTer) in festem Stand.

Aufruf (aus dem Projektverzeichnis Retro25, braucht git):
    python tools/fetch_nes.py

Quelle: https://github.com/MiSTer-devel/NES_MiSTer, Commit COMMIT.
Ziel (unverändert, nicht im Repository; Herkunft in README.retro25.md):
    cores/nes/vendor/   NES.sv, files.qip, NES.qsf, NES.sdc, README.md,
                        COPYING, rtl/
Weggelassen:
  - Cyclone-V-PLL: rtl/pll/, rtl/pll.v, rtl/pll.qip (Ersatz in cores/nes/ip/)
  - Palette/ (Farbpaletten zum Laden über das OSD; Pfade für Windows zu lang),
    releases/ (fertige .rbf), sys/ (kommt aus sys/vendor/mister bzw.
    sys/de25), NES_Q13.*, *.srf, clean.bat
Geholt wird per "sparse checkout" nur das Benötigte — so stören die langen
Pfade unter Palette/ nicht.
Eigene Anpassungen nie dort, sondern in cores/nes/ (Kopie + .patch).
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "https://github.com/MiSTer-devel/NES_MiSTer.git"
COMMIT = "49a0a662e244469ca77b2155746a066df704ffae"   # 2026-09-30
DST = ROOT / "cores" / "nes" / "vendor"
FILES = ["NES.sv", "files.qip", "NES.qsf", "NES.sdc", "README.md", "COPYING"]


def skip(rel: Path) -> bool:
    """True für Dateien unter rtl/, die nicht übernommen werden."""
    return rel.parts[0] == "pll" or rel.name in ("pll.v", "pll.qip")


README = """# NES_MiSTer (unverändert)

Herkunft: {repo}, Commit `{commit}`.
Geholt mit `python tools/fetch_nes.py` — hier nichts von Hand ändern.

Weggelassen:

- Cyclone-V-PLL `rtl/pll/`, `rtl/pll.v`, `rtl/pll.qip` (Ersatz in
  `cores/nes/ip/`).
- `Palette/` (Paletten zum Laden über das OSD), `releases/`, `sys/` (kommt
  aus `sys/vendor/mister` bzw. `sys/de25`), `NES_Q13.*`, `*.srf`,
  `clean.bat`.

Lizenz: GPL-3.0 (`COPYING`). Mit eigener Lizenz im Dateikopf: T65
(`rtl/t65`, BSD-artig, Weitergabe mit Vermerk) und VM2413/eseopll
(`rtl/SOUND/OPLL`, Mitsutaka Okazaki: Weitergabe mit Vermerk erlaubt, aber
nicht verkaufen, nicht kommerziell nutzen). Viele Dateien (Mapper, APU,
Savestates) haben keinen eigenen Vermerk — es gilt `COPYING`.
Retro25 insgesamt: GPL-3.0-or-later.
"""


def git(*args: str) -> None:
    subprocess.run(["git", *args], check=True)


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "nes"
        git("clone", "-q", "--filter=blob:none", "--no-checkout", REPO, str(src))
        git("-C", str(src), "sparse-checkout", "set", "--no-cone",
            *[f"/{n}" for n in FILES], "/rtl/")
        git("-C", str(src), "checkout", "-q", COMMIT)
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
