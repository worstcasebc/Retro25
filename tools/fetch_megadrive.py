# SPDX-License-Identifier: GPL-3.0-or-later
"""Holt MiSTers Mega-Drive-Core (MegaDrive_MiSTer, Nuked-MD) in festem Stand.

Aufruf (aus dem Projektverzeichnis Retro25, braucht git):
    python tools/fetch_megadrive.py

Quelle: https://github.com/MiSTer-devel/MegaDrive_MiSTer, Commit COMMIT
(Nachfolger von Genesis_MiSTer, das seit 2023 ruht).
Ziel (unverändert, nicht im Repository; Herkunft in README.retro25.md):
    cores/megadrive/vendor/   MegaDrive.sv, hps_ext.sv, files.qip,
                              MegaDrive.qsf, MegaDrive.sdc, README.md, rtl/
Weggelassen:
  - Cyclone-V-PLL: rtl/pll/, rtl/pll.v, rtl/pll.qip (Ersatz in cores/megadrive/ip/)
  - Bilder in rtl/nuked-md (*.png, *.jpg), sim/ (Testbench von upstream),
    releases/ (fertige .rbf), sys/ (kommt aus sys/vendor/mister bzw.
    sys/de25), *.srf, clean.bat
Geholt wird per "sparse checkout" nur das Benötigte.
Eigene Anpassungen nie dort, sondern in cores/megadrive/ (Kopie + .patch).
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "https://github.com/MiSTer-devel/MegaDrive_MiSTer.git"
COMMIT = "becbdee78c48e6eb536871cd03c869f43d7afa4d"   # 2026-10-05
DST = ROOT / "cores" / "megadrive" / "vendor"
FILES = ["MegaDrive.sv", "hps_ext.sv", "files.qip", "MegaDrive.qsf", "MegaDrive.sdc", "README.md"]


def skip(rel: Path) -> bool:
    """True für Dateien unter rtl/, die nicht übernommen werden."""
    return (rel.parts[0] == "pll" or rel.name in ("pll.v", "pll.qip")
            or rel.suffix.lower() in (".png", ".jpg"))


README = """# MegaDrive_MiSTer (unverändert)

Herkunft: {repo}, Commit `{commit}`.
Geholt mit `python tools/fetch_megadrive.py` — hier nichts von Hand ändern.

Weggelassen:

- Cyclone-V-PLL `rtl/pll/`, `rtl/pll.v`, `rtl/pll.qip` (Ersatz in
  `cores/megadrive/ip/`).
- Bilder in `rtl/nuked-md/`, `sim/`, `releases/`, `sys/` (kommt aus
  `sys/vendor/mister` bzw. `sys/de25`), `*.srf`, `clean.bat`.

Lizenz: GPL-2.0-or-later (Dateiköpfe, Copyright Alexey Melnikov u. a.);
Nuked-MD (`rtl/nuked-md`, Copyright nukeykt) GPL-2.0-or-later laut
`rtl/nuked-md/LICENSE` und Dateiköpfen; VM2413 (`rtl/VM2413`, Mitsutaka
Okazaki) Weitergabe mit Vermerk, nicht kommerziell. Retro25 insgesamt:
GPL-3.0-or-later.
"""


def git(*args: str) -> None:
    subprocess.run(["git", *args], check=True)


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "megadrive"
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
