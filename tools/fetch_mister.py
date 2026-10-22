# SPDX-License-Identifier: GPL-3.0-or-later
"""Holt MiSTers Framework (sys/) und den Template-Core in festem Stand.

Aufruf (aus dem Projektverzeichnis Retro25, braucht git):
    python tools/fetch_mister.py

Quelle: https://github.com/MiSTer-devel/Template_MiSTer, Commit COMMIT.
Ziele (unverändert, nicht im Repository — GPL, siehe LICENSE und die README dort):
    sys/vendor/mister/       Inhalt von sys/ (Framework aller MiSTer-Cores)
    cores/template/vendor/   Template.sv, rtl/, Template.qsf/.sdc, files.qip
Eigene Anpassungen nie dort, sondern in sys/de25/ bzw. cores/template/.
Ein neuer Stand: COMMIT ändern, Skript laufen lassen, Unterschiede prüfen.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "https://github.com/MiSTer-devel/Template_MiSTer.git"
COMMIT = "9c8eadb40067c8ce3aef90899844f62d688ac73a"   # 2026-10-10

TARGETS = {
    "sys": ROOT / "sys" / "vendor" / "mister",
    "Template.sv": ROOT / "cores" / "template" / "vendor" / "Template.sv",
    "rtl": ROOT / "cores" / "template" / "vendor" / "rtl",
    "Template.qsf": ROOT / "cores" / "template" / "vendor" / "Template.qsf",
    "Template.sdc": ROOT / "cores" / "template" / "vendor" / "Template.sdc",
    "files.qip": ROOT / "cores" / "template" / "vendor" / "files.qip",
    "LICENSE": ROOT / "sys" / "vendor" / "mister" / "LICENSE",
}

README = """# MiSTer-Framework (unverändert)

Herkunft: {repo}, Commit `{commit}`, Ordner `sys/`.
Geholt mit `python tools/fetch_mister.py` — hier nichts von Hand ändern.

Lizenz: GPL-2.0 (LICENSE dieses Ordners, aus Template_MiSTer); einzelne
Dateien GPL-2.0-or-later bzw. GPL-3.0-or-later laut Dateikopf; `ascal.vhd`
(TEMLIB) frei verwendbar. Retro25 insgesamt: GPL-3.0-or-later.

Angepasste Fassungen für das DE25-Nano liegen in `sys/de25/`.
"""


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "template"
        subprocess.run(["git", "clone", "-q", "--filter=blob:none", REPO, str(src)], check=True)
        subprocess.run(["git", "-C", str(src), "checkout", "-q", COMMIT], check=True)
        for name, dst in TARGETS.items():
            s = src / name
            if dst.exists():
                shutil.rmtree(dst) if dst.is_dir() else dst.unlink()
            dst.parent.mkdir(parents=True, exist_ok=True)
            if s.is_dir():
                shutil.copytree(s, dst)
            else:
                shutil.copy2(s, dst)
            print(f"{name:14s} -> {dst.relative_to(ROOT)}")
    # Cores binden `include "sys/emu_ports.vh" ein: Suchpfad sys/include.
    inc = ROOT / "sys" / "include" / "sys"
    inc.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "sys" / "vendor" / "mister" / "emu_ports.vh", inc / "emu_ports.vh")
    (ROOT / "sys" / "vendor" / "mister" / "README.md").write_text(
        README.format(repo=REPO, commit=COMMIT), encoding="utf-8")
    (ROOT / "cores" / "template" / "vendor" / "README.md").write_text(
        f"# Template_MiSTer (unverändert)\n\nHerkunft: {REPO}, Commit `{COMMIT}`.\n"
        "Geholt mit `python tools/fetch_mister.py`. Lizenz: GPL-2.0 "
        "(siehe sys/vendor/mister/LICENSE).\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
