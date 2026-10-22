# SPDX-License-Identifier: GPL-3.0-or-later
"""Richtet ein frisch geklontes Retro25 ein: holt den Fremdcode, erzeugt die
angepassten Kopien und meldet, was der Nutzer selbst beisteuern muss.

Aufruf (aus dem Projektverzeichnis Retro25, braucht git und Python 3.10+):
    python tools/setup.py            alles holen und erzeugen
    python tools/setup.py --check    nur prüfen, was fehlt

Warum ein Skript? Fremdcode (MiSTer-Framework, Main_MiSTer, Menü, C64,
MemTest, z486) liegt aus Lizenzgründen nicht im Repository. Jedes
fetch-Skript holt seinen Teil aus einem festen Commit des Originals nach
vendor/; danach entstehen die angepassten Kopien (pro/) aus den Patches:
    tools/apply_patches.py     C64, Menü, MemTest, sys
    cores/z486/make_pro.py     z486 (Textersetzungen)
Nicht automatisch (Lizenz/Urheberrecht, siehe README.md):
    - Terasics HPS-System (GHRD) -> tools/fetch_hps.py <Paket>/Demonstration/SoC_FPGA/GHRD sys/hps
    - C64- und 1541-ROMs         -> roms/, dann tools/make_c64_roms.py
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

STEPS = [
    ("MiSTer-Framework (sys) + Template", ["tools/fetch_mister.py"], ROOT / "sys/vendor/mister/sys_top.v"),
    ("Main_MiSTer", ["tools/fetch_main.py"], ROOT / "linux/vendor/main_mister/main.cpp"),
    ("Menü-Core", ["tools/fetch_menu.py"], ROOT / "cores/menu/vendor/menu.sv"),
    ("C64-Core", ["tools/fetch_c64.py"], ROOT / "cores/c64/vendor/c64.sv"),
    ("MemTest-Core", ["tools/fetch_memtest.py"], ROOT / "cores/memtest/vendor/memtest.sv"),
    ("z486-Core", ["tools/fetch_z486.py"], ROOT / "cores/z486/vendor/z486_mister.sv"),
    ("z486 Boot-ROMs, FreeDOS, MISTERFS", ["tools/fetch_z486.py", "--roms"], ROOT / "roms/z486/boot0.rom"),
]
GENERATE = [
    ("angepasste Kopien (C64, Menü, MemTest, sys)", ["tools/apply_patches.py"]),
    ("angepasste Kopien z486", ["cores/z486/make_pro.py"]),
]


def run(args: list) -> None:
    print("  $ python " + " ".join(args))
    r = subprocess.run([sys.executable, *args], cwd=ROOT)
    if r.returncode != 0:
        sys.exit(f"Abbruch: python {' '.join(args)} meldete Fehler {r.returncode}")


def main() -> int:
    check = "--check" in sys.argv[1:]
    if not shutil.which("git"):
        sys.exit("git fehlt (https://git-scm.com) — die fetch-Skripte brauchen es")

    print("== Fremdcode")
    for name, args, marker in STEPS:
        if marker.exists():
            print(f"  vorhanden: {name}")
        elif check:
            print(f"  FEHLT:     {name}  (python {' '.join(args)})")
        else:
            print(f"  hole:      {name}")
            run(args)

    if not check:
        print("== Angepasste Kopien")
        for name, args in GENERATE:
            print(f"  erzeuge:   {name}")
            run(args)
        # MiSTers emu_ports.vh unverändert in den Include-Pfad der Cores
        # (sys/include, `include "sys/emu_ports.vh"`)
        dst = ROOT / "sys/include/sys/emu_ports.vh"
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "sys/vendor/mister/emu_ports.vh", dst)
        print("  kopiert:   sys/include/sys/emu_ports.vh")

    print("== Von dir beizusteuern (nicht automatisch)")
    hps = ROOT / "sys/hps/qsys_top.qsys"
    print(f"  {'ok   ' if hps.exists() else 'FEHLT'} Terasics HPS-System: python tools/fetch_hps.py"
          " <Ressourcenpaket>/Demonstration/SoC_FPGA/GHRD sys/hps (siehe README.md)")
    roms = [ROOT / "roms" / n for n in ("basic-901226-01.bin", "kernal-901227-03.bin",
                                         "chargen-901225-01.bin", "dos1541-325302-01+901229-05.bin")]
    have = all(p.exists() for p in roms)
    print(f"  {'ok   ' if have else 'FEHLT'} C64-ROMs in roms/ (siehe roms/README.md),"
          " danach python tools/make_c64_roms.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
