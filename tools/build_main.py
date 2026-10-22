# SPDX-License-Identifier: GPL-3.0-or-later
"""Baut Main_MiSTer für das DE25-Nano in einem arm64-Docker-Container.

Aufruf (aus dem Projektverzeichnis Retro25, braucht Docker Desktop):
    python tools/build_main.py                   bauen
    python tools/build_main.py --deploy HOST     bauen und aufs Board kopieren
    python tools/build_main.py -- DEBUG=1        Rest geht an make
Ergebnis: linux/main/build/MiSTer

Ablauf:
  1. Image retro25-arm64 aus linux/main/docker/Dockerfile bauen (nur beim
     ersten Mal oder mit --rebuild-image).
  2. linux/vendor und linux/main ins Docker-Volume retro25-build kopieren und
     dort linux/main/build.sh laufen lassen. Warum nicht direkt im
     Windows-Ordner? Jeder Dateizugriff über die Laufwerksfreigabe ist im
     QEMU-Container sehr langsam (der Bau dauerte so viele Minuten). Im
     Volume bleiben die Objektdateien liegen: Der zweite Bau übersetzt nur
     Geändertes.
  3. Das fertige Programm nach linux/main/build/MiSTer kopieren.
--deploy HOST (z. B. terasic@192.168.178.125) kopiert MiSTer, install.sh,
MiSTer.ini und board/ per scp nach ~/retro25/ auf dem Board; danach dort
`cd ~/retro25 && sudo ./install.sh` (sudo braucht das Passwort, daher von Hand).

Hinweis: Änderungen am Makefile lösen kein Neuübersetzen aus (die Objekte
hängen nicht davon ab). Dann --clean oder gezielt z. B. `-- -W fpga_io.cpp`.
"""
import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LINUX = ROOT / "linux"
MAIN = LINUX / "main"
OUT = MAIN / "build"
IMAGE = "retro25-arm64"
VOLUME = "retro25-build"

# Läuft im Container: Quellen (/r, nur lesen) -> Volume (/work), bauen, Ergebnis -> /out
SCRIPT = r"""
set -e
[ "$CLEAN" = 1 ] && rm -rf /work/linux
rm -rf /work/linux/vendor /work/linux/main/de25 /work/linux/main/patches
mkdir -p /work/linux/main
cp -r /r/vendor /work/linux/
cp -r /r/main/de25 /r/main/patches /r/main/Makefile /r/main/build.sh /work/linux/main/
cd /work/linux/main
bash build.sh "$@"
cp build/src/bin/MiSTer /out/MiSTer
"""


def run(cmd: list[str], **kw) -> None:
    print("+", " ".join(cmd))
    subprocess.run(cmd, check=True, **kw)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--deploy", metavar="HOST", help="danach per scp nach HOST:~/retro25/ kopieren")
    ap.add_argument("--clean", action="store_true", help="Bauordner im Volume vorher löschen")
    ap.add_argument("--rebuild-image", action="store_true", help="Docker-Image neu bauen")
    ap.add_argument("make_args", nargs="*", help="weitere make-Argumente (nach --)")
    args = ap.parse_args()

    have_image = subprocess.run(["docker", "image", "inspect", IMAGE],
                                capture_output=True).returncode == 0
    if args.rebuild_image or not have_image:
        run(["docker", "build", "--platform", "linux/arm64", "-t", IMAGE, str(MAIN / "docker")])

    OUT.mkdir(parents=True, exist_ok=True)
    run(["docker", "run", "--rm", "--platform", "linux/arm64",
         "--mount", f"type=bind,source={LINUX},target=/r,readonly",
         "--mount", f"type=bind,source={OUT},target=/out",
         "--mount", f"type=volume,source={VOLUME},target=/work",
         "-e", f"CLEAN={1 if args.clean else 0}",
         IMAGE, "bash", "-c", SCRIPT, "build", *args.make_args])
    print(f"Fertig: {OUT / 'MiSTer'}")

    if args.deploy:
        host = args.deploy
        run(["ssh", host, "mkdir -p retro25/board"])
        # MiSTer.ini (Vorlage aus dem Original) nutzt install.sh nur, wenn auf
        # dem Board noch keine liegt.
        run(["scp", "-q", str(OUT / "MiSTer"), str(MAIN / "install.sh"),
             str(LINUX / "vendor" / "main_mister" / "MiSTer.ini"), f"{host}:retro25/"])
        run(["scp", "-q", *[str(p) for p in sorted((MAIN / "board").iterdir())], f"{host}:retro25/board/"])
        run(["ssh", host, "chmod +x retro25/MiSTer retro25/install.sh retro25/board/retro25-switch-hook"])
        print("Auf dem Board:  cd ~/retro25 && sudo ./install.sh")
    return 0


if __name__ == "__main__":
    sys.exit(main())
