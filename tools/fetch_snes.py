# SPDX-License-Identifier: GPL-3.0-or-later
"""Holt MiSTers SNES-Core (SNES_MiSTer) in festem Stand.

Aufruf (aus dem Projektverzeichnis Retro25, braucht git):
    python tools/fetch_snes.py

Quelle: https://github.com/MiSTer-devel/SNES_MiSTer, Commit COMMIT.
Ziel (unverändert, nicht im Repository; Herkunft in README.retro25.md):
    cores/snes/vendor/   SNES.sv, files.qip, SNES.qsf, SNES.sdc, README.md,
                         SNES_Turbo.md, LICENSE, rtl/
Weggelassen:
  - Cyclone-V-PLL: rtl/pll/, rtl/pll.v, rtl/pll.qip (Ersatz in cores/snes/ip/)
  - rtl/sdr.xlsx (Tabelle), hw/ (Schaltpläne, Logikanalysator), smpsim/,
    src/, releases/ (fertige .rbf, boot1.rom), sys/ (kommt aus
    sys/vendor/mister bzw. sys/de25), SNES_Q13.*, *.srf, clean.bat
Geholt wird per "sparse checkout" nur das Benötigte.
Eigene Anpassungen nie dort, sondern in cores/snes/ (Kopie + .patch).
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "https://github.com/MiSTer-devel/SNES_MiSTer.git"
COMMIT = "4c2b74661b4c4c44eefb6b13743fcaf988bc8063"   # 2026-10-31
DST = ROOT / "cores" / "snes" / "vendor"
FILES = ["SNES.sv", "files.qip", "SNES.qsf", "SNES.sdc", "README.md", "SNES_Turbo.md", "LICENSE"]


def skip(rel: Path) -> bool:
    """True für Dateien unter rtl/, die nicht übernommen werden."""
    return (rel.parts[0] == "pll" or rel.name in ("pll.v", "pll.qip")
            or rel.suffix.lower() == ".xlsx")


README = """# SNES_MiSTer (unverändert)

Herkunft: {repo}, Commit `{commit}`.
Geholt mit `python tools/fetch_snes.py` — hier nichts von Hand ändern.

Weggelassen:

- Cyclone-V-PLL `rtl/pll/`, `rtl/pll.v`, `rtl/pll.qip` (Ersatz in
  `cores/snes/ip/`).
- `rtl/sdr.xlsx`, `hw/`, `smpsim/`, `src/`, `releases/`, `sys/` (kommt aus
  `sys/vendor/mister` bzw. `sys/de25`), `SNES_Q13.*`, `*.srf`, `clean.bat`.

Lizenz: GPL-3.0 (`LICENSE`), Autor srg320; MSU-1 u. a. GPL-3.0-or-later
(Alexey Melnikov). Von Quartus erzeugte Megafunction-Dateien
(`rtl/chip/CX4/cx4cache.vhd`, `SA1/SA1MULT.vhd`, `SPC7110/SPC7110_FIFO.vhd`)
tragen Alteras Vermerk. Die `.mif`-Dateien unter `rtl/chip/` (DSP-1, CX4,
BSX) sind Abzüge der Original-Chip-ROMs — nur hier im (nicht
eingecheckten) vendor/, nie in Patches oder im Repository.
Retro25 insgesamt: GPL-3.0-or-later.
"""


def git(*args: str) -> None:
    subprocess.run(["git", *args], check=True)


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "snes"
        git("clone", "-q", "--filter=blob:none", "--no-checkout", REPO, str(src))
        git("-C", str(src), "sparse-checkout", "set", "--no-cone",
            *[f"/{n}" for n in FILES], "/rtl/")
        git("-C", str(src), "checkout", "-q", COMMIT)
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
    (DST / "README.retro25.md").write_text(README.format(repo=REPO, commit=COMMIT), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
