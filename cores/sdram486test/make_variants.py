# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt die Phasen-Varianten des SDRAM-Tests für den z486 (P5 Z3).

Aufruf (aus dem Projektverzeichnis Retro25, QUARTUS_ROOTDIR gesetzt):
    python cores/sdram486test/make_variants.py [Phase ...]     (Grad, Vorgabe: alle)

Je Phase:
  ip/pNNN/pll_486.ip   IOPLL 50 -> 85 MHz, outclk_1 = 85 MHz mit NNN Grad
                       (per ip-deploy; Modulname überall pll_486)
  quartus/sdram486test_pNNN.qsf
                       Revision = Grundprojekt (tools/make_core_qsf.py) mit
                       dieser PLL und PHASE_BCD für die Anzeige
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


def deploy_pll(phase: int) -> None:
    out = HERE / "ip" / f"p{phase:03d}"
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
    cmd = [str(exe), "--component-name=altera_iopll", "--output-name=pll_486",
           f"--output-directory={out}", "--family=Agilex 5", f"--part={DEVICE}"]
    cmd += [f"--component-parameter={k}={v}" for k, v in params.items()]
    r = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    errors = [ln for ln in r.stdout.splitlines() if "Error" in ln]
    if r.returncode or errors:
        print("\n".join(errors) or r.stdout[-2000:])
        sys.exit(f"ip-deploy für {phase} Grad fehlgeschlagen")
    print(f"ip/p{phase:03d}/pll_486.ip")


def make_revision(phase: int) -> None:
    q = HERE / "quartus"
    base = (q / "sdram486test.qsf").read_text(encoding="utf-8")
    ip_line = "set_global_assignment -name IP_FILE ../ip/pll_486.ip"
    if ip_line not in base:
        sys.exit("Grundprojekt ohne ../ip/pll_486.ip — erst tools/make_core_qsf.py sdram486test")
    rev = base.replace(ip_line, f"set_global_assignment -name IP_FILE ../ip/p{phase:03d}/pll_486.ip")
    rev += f"\n# Variante: SDRAM_CLK mit {phase} Grad (make_variants.py)\n"
    rev += f"set_global_assignment -name VERILOG_MACRO \"PHASE_BCD=16'hF{phase:03d}\"\n"
    (q / f"sdram486test_p{phase:03d}.qsf").write_text(rev, encoding="utf-8", newline="\n")
    print(f"quartus/sdram486test_p{phase:03d}.qsf")


def main() -> int:
    phases = [int(p) for p in sys.argv[1:]] or PHASES
    for p in phases:
        deploy_pll(p)
        make_revision(p)
    revs = ["sdram486test"] + [f"sdram486test_p{p:03d}" for p in PHASES
                               if (HERE / "quartus" / f"sdram486test_p{p:03d}.qsf").exists()]
    (HERE / "quartus" / "sdram486test.qpf").write_text(
        "".join(f'PROJECT_REVISION = "{r}"\n' for r in revs), encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
