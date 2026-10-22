# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt die .qsf eines Core-Projekts aus den gemeinsamen sys-Einstellungen.

Aufruf (aus dem Projektverzeichnis Retro25):
    python tools/make_core_qsf.py <core>

Liest cores/<core>/core.tcl (Dateiliste und Makros des Cores, Pfade relativ
zu cores/<core>/) und schreibt cores/<core>/quartus/<core>.qsf und .qpf.
Gemeinsam für alle Cores (aus sys/de25/sys_de25.tcl): Gerät, Konfiguration
(HPS-first), alle Pins, HPS-System (sys/hps, per tools/fetch_hps.py geholt),
sys_top_de25 und die MiSTer-Dateien aus sys/vendor/mister.
Platzhalter in den Vorlagen: {SYS} = Pfad zu sys/, {CORE} = Pfad zum Core,
jeweils relativ zum Quartus-Projektordner.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    core = sys.argv[1]
    core_dir = ROOT / "cores" / core
    proj = core_dir / "quartus"
    proj.mkdir(parents=True, exist_ok=True)
    subst = {"{SYS}": "../../../sys", "{CORE}": ".."}

    def load(p: Path) -> str:
        t = p.read_text(encoding="utf-8")
        for k, v in subst.items():
            t = t.replace(k, v)
        return t.rstrip() + "\n"

    qsf = (f"# {core}.qsf — ERZEUGT von tools/make_core_qsf.py, nicht von Hand ändern.\n"
           f"# Quellen: sys/de25/sys_de25.tcl und cores/{core}/core.tcl\n\n"
           f"# --- Core: {core} ---\n" + load(core_dir / "core.tcl") +
           "\n# --- sys (gemeinsam für alle Cores) ---\n" + load(ROOT / "sys" / "de25" / "sys_de25.tcl"))
    (proj / f"{core}.qsf").write_text(qsf, encoding="utf-8", newline="\n")
    (proj / f"{core}.qpf").write_text(f'QUARTUS_VERSION = "26.1"\nPROJECT_REVISION = "{core}"\n',
                                      encoding="utf-8", newline="\n")
    print(f"geschrieben: {proj / (core + '.qsf')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
