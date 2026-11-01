# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt die Phasen-Varianten des SDRAM-Tests (P5 Z3, P6 Genesis).

Aufruf (aus dem Projektverzeichnis Retro25, QUARTUS_ROOTDIR gesetzt):
    python cores/sdram486test/make_variants.py [Phase ...]          z486: 85 MHz
    python cores/sdram486test/make_variants.py --g107 [Phase ...]   Genesis
(Phase in Grad, Vorgabe: alle acht)

Je Phase:
  ip/pNNN/pll_486.ip   IOPLL 50 -> 85 MHz, outclk_1 = 85 MHz mit NNN Grad
                       (per ip-deploy; Modulname überall pll_486)
  quartus/sdram486test_pNNN.qsf
                       Revision = Grundprojekt (tools/make_core_qsf.py) mit
                       dieser PLL und PHASE_BCD für die Anzeige
Mit --g107 (Genesis_MiSTer taktet sein SDRAM mit 107,386 MHz, CL2, tRCD 2):
  ip/g107_pNNN/pll_486.ip   M 189, N 4 (VCO 2362,5 MHz), C 22 -> 107,386364 MHz
  quartus/sdram486test_g107_pNNN.qsf
                       zusätzlich TESTER_FREQ = 100 MHz: Der Controller wählt
                       daraus CL2, tRCD/tRP 2, tRC 6 (FAST_GRADE) — das
                       Genesis-Timing; der Refresh kommt etwas häufiger.
                       Anzeige: Phase mit Vorsatz "1" (z. B. 1090 = 90 Grad).
Gebaut wird eine Revision mit
    quartus_sh --flow compile sdram486test -c sdram486test_pNNN
(Q:\\cores\\sdram486test\\quartus). Warum mehrere Builds statt einer zur
Laufzeit verstellbaren Phase: In Retro25 stellt nur sys eine PLL um (zwei
umgestellte HVIO-PLLs stören sich, P3).
"""
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
DEVICE = "A5EB013BB23BE4SCS"
PHASES = [0, 45, 90, 135, 180, 225, 270, 315]
BASE_IP = "{CORE}/ip/pll_486.ip"            # Platzhalter in core.tcl


def deploy_pll(phase: int, g107: bool) -> str:
    sub = f"g107_p{phase:03d}" if g107 else f"p{phase:03d}"
    out = HERE / "ip" / sub
    out.mkdir(parents=True, exist_ok=True)
    exe = Path(os.environ["QUARTUS_ROOTDIR"]).parent / "qsys" / "bin" / "ip-deploy.exe"
    params = {
        "gui_reference_clock_frequency": "50.0",
        "gui_use_locked": "true",
        "gui_operation_mode": "direct",
        "gui_number_of_clocks": "2",
        "gui_output_clock_frequency0": "85.0",
        "gui_output_clock_frequency1": "85.0",
        "gui_ps_units1": "degrees",
        "gui_phase_shift_deg1": f"{phase}.0",
    }
    if g107:
        # Teiler von Hand wie tools/make_iopll.py (Genesis: exakt 4725/44 MHz)
        params.update({
            "gui_en_adv_params": "true",
            "gui_multiply_factor": "189",
            "gui_divide_factor_n": "4",
            "gui_divide_factor_c0": "22",
            "gui_divide_factor_c1": "22",
            "gui_output_clock_frequency0": "107.386364",
            "gui_output_clock_frequency1": "107.386364",
        })
    cmd = [str(exe), "--component-name=altera_iopll", "--output-name=pll_486",
           f"--output-directory={out}", "--family=Agilex 5", f"--part={DEVICE}"]
    cmd += [f"--component-parameter={k}={v}" for k, v in params.items()]
    r = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    errors = [ln for ln in r.stdout.splitlines() if "Error" in ln]
    if r.returncode or errors:
        print("\n".join(errors) or r.stdout[-2000:])
        sys.exit(f"ip-deploy für {sub} fehlgeschlagen")
    print(f"ip/{sub}/pll_486.ip")
    return sub


def make_revision(phase: int, sub: str, g107: bool) -> str:
    q = HERE / "quartus"
    base = (q / "sdram486test.qsf").read_text(encoding="utf-8")
    ip_line = "set_global_assignment -name IP_FILE ../ip/pll_486.ip"
    if ip_line not in base:
        sys.exit("Grundprojekt ohne ../ip/pll_486.ip — erst tools/make_core_qsf.py sdram486test")
    name = f"sdram486test_{sub}"
    rev = base.replace(ip_line, f"set_global_assignment -name IP_FILE ../ip/{sub}/pll_486.ip")
    rev += f"\n# Variante: SDRAM_CLK mit {phase} Grad (make_variants.py)\n"
    prefix = "1" if g107 else "F"
    rev += f"set_global_assignment -name VERILOG_MACRO \"PHASE_BCD=16'h{prefix}{phase:03d}\"\n"
    if g107:
        rev += "# Genesis: 107,386 MHz, Controller-Timing für 100 MHz (CL2, tRCD 2)\n"
        rev += "set_global_assignment -name VERILOG_MACRO \"TESTER_FREQ=100000000\"\n"
    (q / f"{name}.qsf").write_text(rev, encoding="utf-8", newline="\n")
    print(f"quartus/{name}.qsf")
    return name


def main() -> int:
    args = sys.argv[1:]
    g107 = "--g107" in args
    phases = [int(p) for p in args if not p.startswith("--")] or PHASES
    for p in phases:
        sub = deploy_pll(p, g107)
        make_revision(p, sub, g107)
    revs = ["sdram486test"] + sorted(f.stem for f in (HERE / "quartus").glob("sdram486test_*.qsf"))
    (HERE / "quartus" / "sdram486test.qpf").write_text(
        "".join(f'PROJECT_REVISION = "{r}"\n' for r in revs), encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
