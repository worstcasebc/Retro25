# SPDX-License-Identifier: GPL-3.0-or-later
"""Holt das HPS-System (Platform Designer, IP, Bootloader) in ein Quartus-Projekt.

Aufruf (aus dem Projektverzeichnis Retro25):
    python tools/fetch_hps.py [Quelle] [Ziel]

Quelle ist Terasics GHRD aus dem DE25-Nano-Ressourcenpaket
(<Paket>\\Demonstration\\SoC_FPGA\\GHRD); ohne Angabe ..\\C64-DE25\\quartus_hps
(GHRD des Vorgängerprojekts). Fehlen die Brücken c64_bridge und disk_bridge,
fügt sys/de25/hps_bridges.tcl sie ein. Default-Ziel ist p0/quartus (für alle
Cores: sys/hps). Kopiert werden nur Quellen, keine Bauerzeugnisse.

Diese Dateien stammen aus Terasics GHRD, dürfen nicht weitergegeben werden
und stehen deshalb nicht im Repository (.gitignore).

Ziel sys/hps (das HPS-System aller Retro25-Cores): Danach wendet das Skript
per qsys-script sys/de25/hps_f2sdram_ports.tcl (drei DDR-Ports für sysmem,
P3) und sys/de25/hps_slim.tcl an (GHRD-Demo- und Debug-Teile raus,
FPGA->HPS-Bridge aus, P5) und erzeugt qsys_top mit qsys-generate neu.
qsys-script braucht ein Quartus-Projekt und trägt dort IP-Dateien ein —
dafür nimmt es ein Wegwerf-Projekt im Temp-Ordner, damit kein Core-Projekt
verändert wird.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SRC = ROOT.parent / "C64-DE25" / "quartus_hps"
DEFAULT_DST = ROOT / "p0" / "quartus"
SYS_HPS = ROOT / "sys" / "hps"
PORTS_TCL = ROOT / "sys" / "de25" / "hps_f2sdram_ports.tcl"
SLIM_TCL = ROOT / "sys" / "de25" / "hps_slim.tcl"
BRIDGES_TCL = ROOT / "sys" / "de25" / "hps_bridges.tcl"
DEVICE = "A5EB013BB23BE4SCS"    # wie sys/de25/sys_de25.tcl

# Wie sw/py/fetch_ghrd.py im C64-Projekt; dazu board.info.
PATTERNS = [
    "qsys_top.qsys",
    "*_subsys/*.qsys",
    "ip/*.ip",
    "ip/qsys_top/*.ip",
    "*_subsys/ip/*/*.ip",
    "custom_ip/**/*",
    "software/u-boot/spl/u-boot-spl-dtb.hex",
    "board.info",
]


def main() -> int:
    if len(sys.argv) > 3:
        sys.exit(__doc__)
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_DST
    if not (src / "qsys_top.qsys").is_file():
        sys.exit(f"{src} enthält kein qsys_top.qsys")

    files = sorted({f for p in PATTERNS for f in src.glob(p)
                    if f.is_file() and not f.name.startswith("._") and ".BAK." not in f.name})
    for f in files:
        target = dst / f.relative_to(src)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, target)
    print(f"{len(files)} Dateien von {src} nach {dst} kopiert.")
    # Brücken immer neu anlegen: so heißen ihre IP-Dateien
    # peripheral_subsys_<name>.ip (wie in sys_de25.tcl), auch wenn die Quelle
    # sie schon von Hand (als mm_bridge_0/1) enthielt
    for old in (dst / "peripheral_subsys" / "ip" / "peripheral_subsys").glob("peripheral_subsys_mm_bridge_*"):
        shutil.rmtree(old) if old.is_dir() else old.unlink()
    run_qsys_script(dst, BRIDGES_TCL)
    print("Brücken c64_bridge/disk_bridge eingefügt.")
    if dst.resolve() == SYS_HPS.resolve():
        # Reste eines früheren Laufs entfernen, sonst benennt Platform Designer
        # die neuen Instanzen um (f2s_vbuf_0 …)
        for old in (dst / "ip" / "qsys_top").glob("qsys_top_f2s_*"):
            shutil.rmtree(old) if old.is_dir() else old.unlink()
        run_qsys_script(dst, PORTS_TCL)
        print("DDR-Ports f2s_vbuf/f2s_ram1/f2s_ram2 in qsys_top eingefügt.")
        run_qsys_script(dst, SLIM_TCL)
        print("ocm, subsys_debug, ACE5-Lite-Übersetzer, ext_hps_f2sdram_master entfernt.")
        generate(dst)
    return 0


def run_qsys_script(dst: Path, script: Path) -> None:
    """Wendet ein qsys-script-Rezept auf dst/qsys_top.qsys an."""
    root = os.environ.get("QUARTUS_ROOTDIR")
    if not root:
        sys.exit("QUARTUS_ROOTDIR fehlt — qsys-script nicht auffindbar")
    exe = Path(root).parent / "qsys" / "bin" / ("qsys-script.exe" if os.name == "nt" else "qsys-script")
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
        (Path(tmp) / "tmp_hps.qpf").write_text('PROJECT_REVISION = "tmp_hps"\n')
        (Path(tmp) / "tmp_hps.qsf").write_text(
            'set_global_assignment -name FAMILY "Agilex 5"\n'
            f"set_global_assignment -name DEVICE {DEVICE}\n")
        cmd = [str(exe), "--system-file=qsys_top.qsys", f"--script={script}",
               f"--quartus-project={Path(tmp) / 'tmp_hps.qpf'}"]
        print("+", " ".join(cmd))
        out = subprocess.run(cmd, cwd=dst, capture_output=True, text=True, errors="replace")
        errors = [ln for ln in out.stdout.splitlines() if "Error" in ln]
        if out.returncode or errors:
            print("\n".join(errors) or out.stdout[-2000:])
            sys.exit(f"{script.name} fehlgeschlagen")


def generate(dst: Path) -> None:
    """Erzeugt qsys_top neu (synth/). Quartus Pro bemerkt eine geänderte .qsys
    beim Core-Bau nicht und nähme sonst das alte qsys_top.v."""
    exe = Path(os.environ["QUARTUS_ROOTDIR"]).parent / "qsys" / "bin" / (
        "qsys-generate.exe" if os.name == "nt" else "qsys-generate")
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
        (Path(tmp) / "tmp_hps.qpf").write_text('PROJECT_REVISION = "tmp_hps"\n')
        (Path(tmp) / "tmp_hps.qsf").write_text(
            'set_global_assignment -name FAMILY "Agilex 5"\n'
            f"set_global_assignment -name DEVICE {DEVICE}\n")
        # custom_ip: dort liegt f2sdram_adapter (wie IP_SEARCH_PATHS im Core)
        cmd = [str(exe), "qsys_top.qsys", "--synthesis=VERILOG", '--family=Agilex 5', f"--part={DEVICE}",
               "--search-path=custom_ip/**/*,$", f"--quartus-project={Path(tmp) / 'tmp_hps.qpf'}"]
        print("+", " ".join(cmd))
        out = subprocess.run(cmd, cwd=dst, capture_output=True, text=True, errors="replace")
        if out.returncode:
            print("\n".join(ln for ln in out.stdout.splitlines() if "Error" in ln) or out.stdout[-2000:])
            sys.exit("qsys-generate fehlgeschlagen")
    print("qsys_top neu erzeugt.")


if __name__ == "__main__":
    sys.exit(main())
