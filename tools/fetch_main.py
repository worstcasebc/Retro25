# SPDX-License-Identifier: GPL-3.0-or-later
"""Holt Main_MiSTer (MiSTers Linux-Programm) in festem Stand.

Aufruf (aus dem Projektverzeichnis Retro25, braucht git):
    python tools/fetch_main.py

Quelle: https://github.com/MiSTer-devel/Main_MiSTer, Commit COMMIT.
Ziel (unverändert, nicht im Repository — GPL-3.0, siehe LICENSE dort):
    linux/vendor/main_mister/
Weggelassen: releases/ (fertige 32-bit-Programme, 72 MB) und die vorgebauten
32-bit-Bibliotheken (*.so) — auf dem DE25-Nano kommen sie aus Ubuntu-Paketen.
Eigene Anpassungen nie dort, sondern in linux/main/ (siehe README dort).
Ein neuer Stand: COMMIT ändern, Skript laufen lassen, Patches prüfen.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "https://github.com/MiSTer-devel/Main_MiSTer.git"
COMMIT = "00bdff0d5b985a3a929978f86f15d930954451a2"   # 2026-10-14
DST = ROOT / "linux" / "vendor" / "main_mister"

README = """# Main_MiSTer (unverändert)

Herkunft: {repo}, Commit `{commit}`.
Geholt mit `python tools/fetch_main.py` — hier nichts von Hand ändern.
Weggelassen: `releases/` und die vorgebauten 32-bit-Bibliotheken (`*.so`).

Lizenz: GPL-3.0 (LICENSE dieses Ordners); Bibliotheken unter `lib/` mit
eigenen Lizenzen (miniz, lzma, zstd, libchdr, md5, libco …, siehe dort).
Retro25 insgesamt: GPL-3.0-or-later.

Die Anpassungen für das DE25-Nano liegen in `linux/main/`.
"""


def ignore(_dir: str, names: list[str]) -> list[str]:
    return [n for n in names if n in (".git", "releases") or n.endswith(".so")]


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "main"
        subprocess.run(["git", "clone", "-q", "--filter=blob:none", "--no-checkout", REPO, str(src)], check=True)
        # Byte-genau auschecken (keine CRLF-Umwandlung unter Windows)
        subprocess.run(["git", "-C", str(src), "config", "core.autocrlf", "false"], check=True)
        subprocess.run(["git", "-C", str(src), "checkout", "-q", COMMIT], check=True)
        if DST.exists():
            shutil.rmtree(DST)
        shutil.copytree(src, DST, ignore=ignore)
    (DST / "README.retro25.md").write_text(README.format(repo=REPO, commit=COMMIT), encoding="utf-8")
    n = sum(1 for p in DST.rglob("*") if p.is_file())
    print(f"Main_MiSTer {COMMIT[:8]} -> {DST.relative_to(ROOT)} ({n} Dateien)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
