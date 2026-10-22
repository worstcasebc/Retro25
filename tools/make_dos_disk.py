# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt Datenträgerabbilder für den z486 und kopiert Ordner darauf:
Festplatte (.vhd, MBR + eine FAT16-Partition), Diskette (.img, 1,44 MB FAT12)
oder CD (.iso, ISO 9660 mit Joliet).

Aufruf (aus dem Projektverzeichnis Retro25, braucht Docker Desktop):
    python tools/make_dos_disk.py AUSGABE [--type hdd|floppy|iso] [--size MB]
                                  [--label NAME] [QUELLE[=DOSORDNER] ...]

Beispiele:
    python tools/make_dos_disk.py roms/z486/games.vhd --size 256 C:/tmp/doom=DOOMINST
    python tools/make_dos_disk.py roms/z486/test.img --type floppy C:/tmp/test=TEST
    python tools/make_dos_disk.py roms/z486/test.iso --type iso C:/tmp/test=TEST

Jede QUELLE (Ordner) wird mit Inhalt nach \\DOSORDNER kopiert (Vorgabe: der
Ordnername in Großbuchstaben). Die Festplatte ist nicht bootfähig — sie gehört
an IDE 0-1 und erscheint unter FreeDOS als D:. Diskette: OSD „Floppy A:“,
CD: OSD „IDE 1-0“ (FreeDOS lädt den CD-Treiber beim Start, Laufwerk E:).

Warum Docker: mkfs.fat, mtools und genisoimage (Linux) erzeugen und
beschreiben ein Abbild, ohne es einzuhängen; unter Windows gibt es dafür kein
Bordmittel. Läuft in einem amd64-Ubuntu-Container (nicht im arm64-Bauimage von
Main).
"""
import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

IMAGE = "ubuntu:22.04"
START = 2048                     # erste Partition ab Sektor 2048 (1 MB)

PREP = r"""
set -e
apt-get -qq update >/dev/null && apt-get -qq install -y dosfstools mtools fdisk genisoimage >/dev/null 2>&1
cd /w
export MTOOLS_SKIP_CHECK=1
"""

# Ordner aus src/ ins FAT-Abbild $IMG kopieren und Inhalt zeigen
COPY_FAT = r"""
for d in src/*; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  mmd -i "$IMG" "::$name"
  mcopy -s -i "$IMG" "$d"/* "::$name/"
done
mdir -i "$IMG" ::
minfo -i "$IMG" | grep -i "free\|cluster" || true
"""

SCRIPTS = {
    "hdd": r"""
truncate -s {size}M disk.img
echo 'start={start}, type=6, bootable' | sfdisk -q disk.img
mkfs.fat -F 16 -n {label} --offset {start} -h {start} disk.img >/dev/null
IMG="disk.img@@$(({start}*512))"
""" + COPY_FAT,
    # 1,44 MB ohne Partitionstabelle, wie eine echte Diskette
    "floppy": r"""
mkfs.fat -C -F 12 -n {label} disk.img 1440 >/dev/null
IMG="disk.img"
""" + COPY_FAT,
    # Joliet für lange Namen unter Windows; DOS (SHSUCDX) liest die 8.3-Namen
    "iso": r"""
genisoimage -quiet -J -r -V {label} -o disk.img src
ls -l disk.img
""",
}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out")
    ap.add_argument("--type", choices=sorted(SCRIPTS), default="hdd")
    ap.add_argument("--size", type=int, default=256, help="nur hdd: Größe in MB (FAT16: höchstens 2047)")
    ap.add_argument("--label", default=None, help="Datenträgername (Vorgabe GAMES bzw. TEST)")
    ap.add_argument("src", nargs="*")
    a = ap.parse_intermixed_args()
    if a.type == "hdd" and not 16 <= a.size <= 2047:
        sys.exit("FAT16-Platte: 16 bis 2047 MB")
    label = (a.label or ("GAMES" if a.type == "hdd" else "TEST")).upper()[:11]
    with tempfile.TemporaryDirectory() as tmp:
        w = Path(tmp)
        (w / "src").mkdir()
        for s in a.src:
            path, _, dos = s.partition("=")
            dos = (dos or Path(path).name).upper()
            if len(dos) > 8:
                sys.exit(f"{dos}: DOS-Ordnernamen höchstens 8 Zeichen")
            shutil.copytree(path, w / "src" / dos)
        script = PREP + SCRIPTS[a.type].format(size=a.size, start=START, label=label)
        (w / "run.sh").write_text(script, encoding="utf-8", newline="\n")
        r = subprocess.run(["docker", "run", "--rm", "--platform", "linux/amd64", "-v", f"{w}:/w",
                            IMAGE, "bash", "/w/run.sh"])
        if r.returncode:
            sys.exit("Docker-Lauf fehlgeschlagen")
        out = Path(a.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(w / "disk.img"), out)
    print(f"{out} ({out.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
