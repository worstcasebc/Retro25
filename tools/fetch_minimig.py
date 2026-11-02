# SPDX-License-Identifier: GPL-3.0-or-later
"""Holt MiSTers Amiga-Core (Minimig-AGA_MiSTer) in festem Stand.

Aufruf (aus dem Projektverzeichnis Retro25, braucht git):
    python tools/fetch_minimig.py

Quelle: https://github.com/MiSTer-devel/Minimig-AGA_MiSTer, Commit COMMIT.
Der Stand passt zum Main_MiSTer-Commit in tools/fetch_main.py (beide vom
2026-10-14): Core und Main teilen sich das Minimig-Protokoll.
Ziel (unverändert, nicht im Repository; Herkunft in README.retro25.md):
    cores/minimig/vendor/   Minimig.sv, hps_ext.v, files.qip, Minimig.qsf,
                            Minimig.sdc, README.md, gpl.txt, rtl/
Weggelassen:
  - Cyclone-V-PLL: rtl/pll/, rtl/pll.v, rtl/pll.qip (Ersatz in cores/minimig/ip/)
  - rtl/sim/ (Simulationsumgebung), releases/ (fertige .rbf, Amiga-Dateien),
    sys/ (kommt aus sys/vendor/mister bzw. sys/de25), doc/, extra/, tools/,
    Minimig_Q13.*, *.srf, clean.bat
Geholt wird per "sparse checkout" nur das Benötigte.
Eigene Anpassungen nie dort, sondern in cores/minimig/ (Kopie + .patch).
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "https://github.com/MiSTer-devel/Minimig-AGA_MiSTer.git"
COMMIT = "d241338"   # 2026-10-14, wird beim Holen zur vollen ID aufgelöst
DST = ROOT / "cores" / "minimig" / "vendor"
FILES = ["Minimig.sv", "hps_ext.v", "files.qip", "Minimig.qsf", "Minimig.sdc", "README.md", "gpl.txt"]


def skip(rel: Path) -> bool:
    """True für Dateien unter rtl/, die nicht übernommen werden."""
    return rel.parts[0] in ("pll", "sim") or rel.name in ("pll.v", "pll.qip")


README = """# Minimig-AGA_MiSTer (unverändert)

Herkunft: {repo}, Commit `{commit}`.
Geholt mit `python tools/fetch_minimig.py` — hier nichts von Hand ändern.

Weggelassen:

- Cyclone-V-PLL `rtl/pll/`, `rtl/pll.v`, `rtl/pll.qip` (Ersatz in
  `cores/minimig/ip/`).
- `rtl/sim/`, `releases/`, `sys/` (kommt aus `sys/vendor/mister` bzw.
  `sys/de25`), `doc/`, `extra/`, `tools/`, `Minimig_Q13.*`, `*.srf`,
  `clean.bat`.

Lizenz: GPL-3.0 (`gpl.txt`); fx68k GPL-3.0-or-later (Jorge Cwik); `rtl/ide.v`
BSD-2-Clause (Alexey Melnikov). Kickstart-ROMs gehören nicht dazu: Der Nutzer
legt sie selbst in `games/Amiga` ab.
Retro25 insgesamt: GPL-3.0-or-later.
"""


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, stdout=subprocess.PIPE, text=True).stdout.strip()


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "minimig"
        git("-c", "core.longpaths=true", "clone", "-q", "--filter=blob:none", "--no-checkout", REPO, str(src))
        git("-C", str(src), "sparse-checkout", "set", "--no-cone",
            *[f"/{n}" for n in FILES], "/rtl/")
        git("-C", str(src), "checkout", "-q", COMMIT)
        full = git("-C", str(src), "rev-parse", "HEAD")
        if DST.exists():
            shutil.rmtree(DST)
        DST.mkdir(parents=True)
        for name in FILES:
            shutil.copy2(src / name, DST / name)
            print(f"{name:14s} -> {(DST / name).relative_to(ROOT)}")
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
    (DST / "README.retro25.md").write_text(README.format(repo=REPO, commit=full), encoding="utf-8")
    print("Commit", full)
    return 0


if __name__ == "__main__":
    sys.exit(main())
