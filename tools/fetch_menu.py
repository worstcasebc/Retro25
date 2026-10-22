# SPDX-License-Identifier: GPL-3.0-or-later
"""Holt MiSTers Menü-Core (Menu_MiSTer) in festem Stand.

Aufruf (aus dem Projektverzeichnis Retro25, braucht git):
    python tools/fetch_menu.py

Quelle: https://github.com/MiSTer-devel/Menu_MiSTer, Commit COMMIT.
Ziel (unverändert, nicht im Repository — GPL-2.0-or-later laut Dateiköpfen; Herkunft
      in README.retro25.md — nicht README.md, das träfe unter Windows die
      Readme.md des Originals):
    cores/menu/vendor/   menu.sv, rtl/ (ohne die Cyclone-V-PLL), files.qip,
                         menu.qsf (nur zum Nachsehen), Readme.md
Eigene Anpassungen nie dort, sondern in cores/menu/ (Kopie + .patch).
Ein neuer Stand: COMMIT ändern, Skript laufen lassen, Unterschiede prüfen.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "https://github.com/MiSTer-devel/Menu_MiSTer.git"
COMMIT = "fa83dc15b9545b58021f62738f0d69bba71ab187"   # 2026-10-14
DST = ROOT / "cores" / "menu" / "vendor"
FILES = ["menu.sv", "files.qip", "menu.qsf", "Readme.md"]
RTL_SKIP = {"pll", "pll.v", "pll.qip"}   # Cyclone-V-PLL, ersetzt durch cores/menu/ip/pll_menu.ip

README = """# Menu_MiSTer (unverändert)

Herkunft: {repo}, Commit `{commit}`.
Geholt mit `python tools/fetch_menu.py` — hier nichts von Hand ändern.
Weggelassen: `rtl/pll*` (Cyclone-V-PLL; Ersatz `cores/menu/ip/pll_menu.ip`),
`releases/`, `sys/` (kommt aus `sys/vendor/mister` bzw. `sys/de25`).

Lizenz: GPL-2.0-or-later (Dateiköpfe, Copyright Sorgelig); ein eigenes
LICENSE liegt dem Repository nicht bei. Retro25 insgesamt: GPL-3.0-or-later.
"""


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "menu"
        subprocess.run(["git", "clone", "-q", "--filter=blob:none", REPO, str(src)], check=True)
        subprocess.run(["git", "-C", str(src), "checkout", "-q", COMMIT], check=True)
        if DST.exists():
            shutil.rmtree(DST)
        DST.mkdir(parents=True)
        for name in FILES:
            shutil.copy2(src / name, DST / name)
            print(f"{name:14s} -> {(DST / name).relative_to(ROOT)}")
        (DST / "rtl").mkdir()
        for p in sorted((src / "rtl").iterdir()):
            if p.name in RTL_SKIP:
                continue
            shutil.copy2(p, DST / "rtl" / p.name)
            print(f"rtl/{p.name:10s} -> {(DST / 'rtl' / p.name).relative_to(ROOT)}")
    (DST / "README.retro25.md").write_text(README.format(repo=REPO, commit=COMMIT), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
