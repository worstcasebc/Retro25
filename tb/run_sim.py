# SPDX-License-Identifier: GPL-3.0-or-later
"""Simuliert Testbenches mit Icarus Verilog.

Aufruf (aus dem Projektverzeichnis):
    python tb/run_sim.py                 alle tb/tb_*.v
    python tb/run_sim.py tb_p0_regs      nur eine Testbench
    python tb/run_sim.py tb_p0_regs -w   zusätzlich GTKWave mit der .vcd öffnen

Jede Testbench muss am Ende "PASS: <name>" ausgeben; jede Zeile mit "FAIL"
gilt als Fehler. Wellenformen landen in tb/build/<name>.vcd.

Icarus übersetzt alle eigenen .v-Dateien unter RTL_DIRS (ohne vendor/, pro/, quartus/, ohne
von Quartus erzeugte IP-Dateien unter ip/ und ohne ICARUS_SKIP).
Testbenches mit der Zeile "// Simulator: Questa" laufen über Questa (im
Quartus-Paket); sie nennen im Kopf selbst, was sie brauchen:
    // Dateien: pfad/a.v pfad/*.sv ...   (relativ zum Projekt, Muster erlaubt)
    // Include: verzeichnis ...          (Suchpfade für `include)
    // Makros:  NAME NAME=WERT ...
Abgeleitet von tb/run_sim.py aus C64-DE25.
"""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "tb" / "build"
ICARUS_DIR = Path(r"C:\iverilog")  # Standardpfad des Windows-Installers
QUESTA_DIR = Path("C:/altera_pro/26.1/questa_fse/win64")
RTL_DIRS = ["p0/rtl", "sys/de25", "cores/testpattern", "cores/c64/rtl"]
# Dateien mit MiSTer-SystemVerilog-Eigenheiten: nur über Questa.
ICARUS_SKIP = {"sys/de25/sys_top_de25.v"}
QUESTA_MARKER = "// Simulator: Questa"


def find_tool(name: str, fallback: Path) -> str:
    """Sucht ein Werkzeug im PATH, sonst am Standard-Installationsort."""
    found = shutil.which(name)
    if found:
        return found
    if fallback.exists():
        return str(fallback)
    sys.exit(f"{name} nicht gefunden (weder im PATH noch unter {fallback})")


def rtl_files() -> list[str]:
    files = []
    for d in RTL_DIRS:
        files += [p.relative_to(ROOT).as_posix() for p in sorted((ROOT / d).rglob("*.v"))
                  if "vendor" not in p.parts and "ip" not in p.parts and "pro" not in p.parts and "quartus" not in p.parts and p.relative_to(ROOT).as_posix() not in ICARUS_SKIP]
    return files


def header_values(source: str, key: str) -> list[str]:
    """Sammelt die Werte aller Kopfzeilen "// <key>: a b c"."""
    out = []
    for ln in source.splitlines():
        ln = ln.strip()
        if ln.startswith(f"// {key}:"):
            out += ln.split(":", 1)[1].split()
    return out


def run_tb_questa(name: str, source: str) -> bool:
    """Übersetzt die im Kopf genannten Dateien mit Questa und simuliert."""
    tool = {t: find_tool(t, QUESTA_DIR / f"{t}.exe") for t in ("vlib", "vlog", "vsim")}
    files = []
    for pat in header_values(source, "Dateien"):
        hits = sorted(p.relative_to(ROOT).as_posix() for p in ROOT.glob(pat))
        if not hits:
            print(f"FAIL: keine Datei passt zu {pat}")
            return False
        files += [h for h in hits if h not in files]
    incdirs = [f"+incdir+{d}" for d in header_values(source, "Include")]
    macros = [f"+define+{m}" for m in header_values(source, "Makros")]
    work = BUILD / "questa" / name
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    rel = work.relative_to(ROOT).as_posix()
    lib = f"{rel}/work"
    subprocess.run([tool["vlib"], lib], cwd=ROOT, capture_output=True, text=True)
    comp = subprocess.run([tool["vlog"], "-sv", "-quiet", "-work", lib, *incdirs, *macros,
                           f"tb/{name}.v", *files], cwd=ROOT, capture_output=True, text=True)
    if comp.returncode != 0:
        print(comp.stdout + comp.stderr)
        return False
    sim = subprocess.run([tool["vsim"], "-c", "-quiet", "-lib", lib, "-l", f"{rel}/transcript",
                          "-wlf", f"{rel}/vsim.wlf", name, "-do", "run -all; quit -f"],
                         cwd=ROOT, capture_output=True, text=True)
    output = sim.stdout + sim.stderr
    lines = [ln[2:] for ln in output.splitlines() if ln.startswith("# ") and not ln.startswith("# //")]
    print("\n".join(ln for ln in lines if ln.strip()))
    text = "\n".join(lines)
    return f"PASS: {name}" in text and "FAIL" not in text and "** Error" not in output


def run_tb(name: str) -> bool:
    """Übersetzt und simuliert eine Testbench."""
    source = (ROOT / "tb" / f"{name}.v").read_text(encoding="utf-8")
    if QUESTA_MARKER in source:
        return run_tb_questa(name, source)
    iverilog = find_tool("iverilog", ICARUS_DIR / "bin" / "iverilog.exe")
    vvp = find_tool("vvp", ICARUS_DIR / "bin" / "vvp.exe")
    helpers = [f"tb/{p.name}" for p in sorted((ROOT / "tb").glob("*.v")) if not p.name.startswith("tb_")]
    out = BUILD / f"{name}.vvp"

    comp = subprocess.run([iverilog, "-g2005", "-Wall", "-Wno-timescale", "-s", name, "-o", str(out),
                           f"tb/{name}.v", *helpers, *rtl_files()],
                          cwd=ROOT, capture_output=True, text=True)
    if comp.returncode != 0 or comp.stderr.strip():
        print(comp.stdout + comp.stderr)
        if comp.returncode != 0:
            return False

    sim = subprocess.run([vvp, str(out)], cwd=ROOT, capture_output=True, text=True)
    output = sim.stdout + sim.stderr
    print(output.strip())
    return sim.returncode == 0 and f"PASS: {name}" in output and "FAIL" not in output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("testbench", nargs="*", help="z. B. tb_p0_regs (Default: alle)")
    parser.add_argument("-w", "--wave", action="store_true", help="GTKWave öffnen")
    args = parser.parse_args()

    BUILD.mkdir(parents=True, exist_ok=True)
    names = args.testbench or [p.stem for p in sorted((ROOT / "tb").glob("tb_*.v"))]
    failed = [n for n in names if not run_tb(n)]

    if args.wave:
        gtkwave = find_tool("gtkwave", ICARUS_DIR / "gtkwave" / "bin" / "gtkwave.exe")
        for n in names:
            subprocess.Popen([gtkwave, str(BUILD / f"{n}.vcd")])

    print(f"\n{len(names) - len(failed)}/{len(names)} Testbenches bestanden")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
