# SPDX-License-Identifier: GPL-3.0-or-later
"""Holt MiSTers SDRAM-Test (MemTest_MiSTer) in festem Stand.

Aufruf (aus dem Projektverzeichnis Retro25, braucht git):
    python tools/fetch_memtest.py

Quelle: https://github.com/MiSTer-devel/MemTest_MiSTer, Commit COMMIT.
Ziel (unverändert, nicht im Repository; Herkunft in README.retro25.md):
    cores/memtest/vendor/   memtest.sv, memtest.sdc, README.md, rtl/ (ohne die
                            Cyclone-V-PLLs pll*, vpll*)
Weggelassen: releases/, img/, sys/, "PLL calculations.xlsx".
Eigene Anpassungen nie dort, sondern in cores/memtest/ (Kopie + .patch).
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "https://github.com/MiSTer-devel/MemTest_MiSTer.git"
COMMIT = "86f89561b325d329ab96dfa6097d895e79ded36a"   # 2026-06-23
DST = ROOT / "cores" / "memtest" / "vendor"
FILES = ["memtest.sv", "memtest.sdc", "README.md"]
RTL_SKIP_PREFIX = ("pll", "vpll")   # Cyclone-V-PLLs, ersetzt durch cores/memtest/ip/

README = """# MemTest_MiSTer (unverändert)

Herkunft: {repo}, Commit `{commit}`.
Geholt mit `python tools/fetch_memtest.py` — hier nichts von Hand ändern.
Weggelassen: `rtl/pll*`, `rtl/vpll*` (Cyclone-V-PLLs; Ersatz in
`cores/memtest/ip/`), `releases/`, `img/`, `sys/` (kommt aus
`sys/vendor/mister` bzw. `sys/de25`), die PLL-Tabelle als Excel-Datei.

Lizenz: `memtest.sv` GPL-2.0-or-later (Dateikopf, Copyright Sorgelig); die
Dateien in `rtl/` (sdram.v, tester.v, vgaout.v, rnd_vec_gen.v) haben keinen
Lizenzvermerk — vor einer Veröffentlichung klären. Retro25 insgesamt:
GPL-3.0-or-later.
"""


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "memtest"
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
            if p.name.startswith(RTL_SKIP_PREFIX) or p.is_dir():
                continue
            shutil.copy2(p, DST / "rtl" / p.name)
            print(f"rtl/{p.name:14s} -> {(DST / 'rtl' / p.name).relative_to(ROOT)}")
    (DST / "README.retro25.md").write_text(README.format(repo=REPO, commit=COMMIT), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
