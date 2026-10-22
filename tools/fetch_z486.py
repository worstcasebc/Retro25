# SPDX-License-Identifier: GPL-3.0-or-later
"""Holt den 486-PC-Core z486_MiSTer samt CPU (Submodul z486) in festem Stand.

Aufruf (aus dem Projektverzeichnis Retro25, braucht git):
    python tools/fetch_z486.py           Quellen nach cores/z486/vendor
    python tools/fetch_z486.py --roms    nur Boot-ROMs, FreeDOS-Platte und
                                         misterfs.exe (ao486, gemeinsamer
                                         Ordner) nach roms/z486 (lokal)

Quelle: https://github.com/nand2mario/z486_MiSTer, Commit COMMIT; die CPU
src/z486 im Stand, den dieser Commit als Submodul festlegt.
Ziel (unverändert, nicht im Repository; Herkunft in README.retro25.md):
    cores/z486/vendor/   z486_mister.sv, Projektdateien, src/, tests/, verilator/
Weggelassen:
  - sys/ (kommt aus sys/vendor/mister bzw. sys/de25)
  - Cyclone-V-PLLs: rtl/, profiles/ (Ersatz später in cores/z486/ip/)
  - src/z486/boards/ (Tops für andere Platinen) und die Hilfsskripte für
    Seed-Sweeps (*.py im Wurzelordner)
  - verilator/freedos.zip (6 MB Plattenabbild) und alle *.rom (Boot-ROMs;
    boot1.rom = Tseng-ET4000-BIOS, proprietär) — beides nicht im Repo; --roms
    holt sie aus demselben Commit nach roms/z486/ (von git ignoriert), das
    Plattenabbild ausgepackt als freedos.vhd
  - verilator/cosim/86Box (Submodul, nur für die Co-Simulation)
Eigene Anpassungen nie dort, sondern in cores/z486/ (Kopie + .patch).
"""
import io
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "https://github.com/nand2mario/z486_MiSTer.git"
COMMIT = "4b8b75ff0c408d416337bf8e9273014b05558d02"   # 2026-10-12
DST = ROOT / "cores" / "z486" / "vendor"
FILES = ["z486_mister.sv", "z486_mister_sim.sv", "files.qip", "backend.qip", "z486_mister.qsf",
         "z486_mister.sdc", "z486_mister.clk_sys_top_setup.tcl", "Makefile", "README.md"]
DIRS = ["src", "tests", "verilator"]


def skip(rel: Path) -> bool:
    """True für Dateien unter DIRS, die nicht übernommen werden."""
    parts = rel.parts
    if parts[:3] == ("src", "z486", "boards") or parts[:3] == ("verilator", "cosim", "86Box"):
        return True
    if rel.name == "freedos.zip" or rel.suffix == ".rom" or rel.name == ".git":
        return True
    return False


README = """# z486_MiSTer (unverändert, ohne Boot-ROMs)

Herkunft: {repo}, Commit `{commit}`; CPU `src/z486` aus
https://github.com/nand2mario/z486.git, Commit `{sub}` (Submodul-Stand).
Geholt mit `python tools/fetch_z486.py` — hier nichts von Hand ändern.

Weggelassen:

- `sys/` (kommt aus `sys/vendor/mister` bzw. `sys/de25`).
- Cyclone-V-PLLs `rtl/` und `profiles/` (Takte laut Upstream: production
  85 MHz/180°, debug 65 MHz/180°, base 50 MHz/225°; SDRAM-Takt = zweiter
  PLL-Ausgang).
- `src/z486/boards/` (Tops für DE10-Nano-Demo, KV260 usw.), Seed-Sweep-
  Skripte (`*.py` im Wurzelordner).
- `verilator/freedos.zip` und alle `*.rom` (Boot-ROMs: `boot0.rom` =
  Bochs-BIOS, LGPL; `boot1.rom` = Tseng-ET4000-VGA-BIOS, proprietär).
- `verilator/cosim/86Box` (Submodul für die Co-Simulation).

Lizenz: CPU (`src/z486`) Apache-2.0, aber laut `src/z486/LICENSE-SCOPE.md` nur
für `*.sv`, `*.svh`, `*.py`, `*.md` — **`ucode.hex` (rekonstruierter
Intel-Microcode) und daraus erzeugte Dateien (`ucode.mif`, Bitstreams) sind
ausgenommen**. z486_MiSTer selbst hat keine LICENSE-Datei; übernommene
MiSTer/ao486-Teile (`src/soc`, `src/common`) tragen eigene Vermerke.
Vor einer Veröffentlichung von Retro25 klären; Bitstreams nicht weitergeben.
Retro25 insgesamt: GPL-3.0-or-later.
"""


def copy_tree(src: Path, rel_root: Path) -> int:
    n = 0
    for p in sorted((src / rel_root).rglob("*")):
        rel = p.relative_to(src)
        if any(part == ".git" for part in rel.parts) or p.is_dir() or skip(rel):
            continue
        out = DST / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, out)
        n += 1
    return n


ROMS = {"boot0.rom": 65536, "boot1.rom": 32768}   # Bochs-BIOS (LGPL), ET4000-VGA-BIOS (proprietär)
AO486_RAW = ("https://raw.githubusercontent.com/MiSTer-devel/ao486_MiSTer/"
             "628ddbcb101f836812981b06367b5080161fad4f")   # 2026-10-06


def fetch_roms() -> int:
    """Boot-ROMs aus verilator/ im festen Commit nach roms/z486/ (nur lokal)."""
    out = ROOT / "roms" / "z486"
    out.mkdir(parents=True, exist_ok=True)
    base = REPO.replace("github.com", "raw.githubusercontent.com").removesuffix(".git")
    for name, size in ROMS.items():
        data = urllib.request.urlopen(f"{base}/{COMMIT}/verilator/{name}").read()
        if len(data) != size:
            sys.exit(f"{name}: {len(data)} statt {size} Bytes")
        (out / name).write_bytes(data)
        print(f"roms/z486/{name} ({size} Bytes)")
    # FreeDOS-Testplatte (32 MB, FAT16) aus freedos.zip; Main nimmt Rohabbilder
    # mit der Endung .vhd
    data = urllib.request.urlopen(f"{base}/{COMMIT}/verilator/freedos.zip").read()
    img = zipfile.ZipFile(io.BytesIO(data)).read("freedos.img")
    if len(img) != 32 * 1024 * 1024 or img[510:512] != b"\x55\xaa":
        sys.exit("freedos.img: unerwartete Größe oder kein MBR")
    (out / "freedos.vhd").write_bytes(img)
    print(f"roms/z486/freedos.vhd ({len(img)} Bytes)")
    # DOS-Treiber des gemeinsamen Ordners (MIT-Lizenz) aus ao486_MiSTer; der
    # z486 hat keinen eigenen, nutzt aber denselben Briefkasten (CE000)
    data = urllib.request.urlopen(AO486_RAW + "/releases/drv/misterfs.exe").read()
    if len(data) != 7005 or data[:2] != b"MZ":
        sys.exit(f"misterfs.exe: {len(data)} Bytes, unerwartet")
    (out / "misterfs.exe").write_bytes(data)
    print(f"roms/z486/misterfs.exe ({len(data)} Bytes)")
    return 0


def main() -> int:
    if sys.argv[1:] == ["--roms"]:
        return fetch_roms()
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "z486"
        git = ["git", "-c", "core.longpaths=true", "-C", str(src)]
        subprocess.run(["git", "clone", "-q", REPO, str(src)], check=True)
        subprocess.run(git + ["checkout", "-q", COMMIT], check=True)
        subprocess.run(git + ["submodule", "update", "-q", "--init", "src/z486"], check=True)
        full = subprocess.run(git + ["rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
        sub = subprocess.run(git + ["-C", "src/z486", "rev-parse", "HEAD"], capture_output=True, text=True,
                             check=True).stdout.strip()
        if DST.exists():
            shutil.rmtree(DST)
        DST.mkdir(parents=True)
        for name in FILES:
            shutil.copy2(src / name, DST / name)
        print(f"{len(FILES)} Projektdateien -> {DST.relative_to(ROOT)}")
        for d in DIRS:
            print(f"{d}/: {copy_tree(src, Path(d))} Dateien")
    (DST / "README.retro25.md").write_text(README.format(repo=REPO, commit=full, sub=sub), encoding="utf-8")
    print(f"z486_MiSTer {full[:8]}, CPU {sub[:8]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
