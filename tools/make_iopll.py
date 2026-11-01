# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt eine feste Agilex-5-IOPLL (.ip) mit vorgegebenen Teilern.

Aufruf (aus dem Projektverzeichnis Retro25, Quartus Pro im PATH bzw.
QUARTUS_ROOTDIR gesetzt):
    python tools/make_iopll.py <ausgabe.ip> M N C0[@grad] [C1[@grad] ...]
Beispiel (NES, 85,909 MHz exakt, 4. Ausgang +90 Grad für SDRAM_CLK):
    python tools/make_iopll.py cores/nes/ip/pll_nes.ip 189 5 22 44 88 22@90

Warum Teiler statt Wunschfrequenz? Die IOPLL des Agilex 5 ist ganzzahlig
(kein fraktionales M wie die Cyclone-V-PLL). Wählt man die Frequenz, sucht
der IP-Editor selbst Teiler und trifft MiSTers krumme Takte oft nur grob.
Mit M/N/C von Hand (VCO = 50 MHz * M / N, Ausgang = VCO / C) lässt sich
der beste Treffer vorher ausrechnen — wie bei cores/c64/ip/pll_c64.
Referenztakt 50 MHz (CLK_50M), Betriebsart "direct", locked-Ausgang an.
Ausgänge heißen outclk_0 … (Modulname = Dateiname ohne .ip).
"""
import os
import subprocess
import sys
from pathlib import Path

DEVICE = "A5EB013BB23BE4SCS"
REF_MHZ = 50.0


def main() -> int:
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    out = Path(sys.argv[1]).resolve()
    m, n = int(sys.argv[2]), int(sys.argv[3])
    outs = []
    for arg in sys.argv[4:]:
        c, _, deg = arg.partition("@")
        outs.append((int(c), float(deg or 0)))
    vco = REF_MHZ * m / n
    params = {
        "gui_reference_clock_frequency": f"{REF_MHZ}",
        "gui_use_locked": "true",
        "gui_operation_mode": "direct",
        "gui_en_adv_params": "true",
        "gui_multiply_factor": str(m),
        "gui_divide_factor_n": str(n),
        "gui_number_of_clocks": str(len(outs)),
    }
    print(f"VCO {vco:.4f} MHz (PFD {REF_MHZ / n:.4f} MHz)")
    for i, (c, deg) in enumerate(outs):
        params[f"gui_divide_factor_c{i}"] = str(c)
        params[f"gui_output_clock_frequency{i}"] = f"{vco / c:.6f}"
        if deg:
            params[f"gui_ps_units{i}"] = "degrees"
            params[f"gui_phase_shift_deg{i}"] = f"{deg}"
        print(f"  outclk_{i}: C {c:3d} -> {vco / c:.6f} MHz" + (f", {deg:+.1f} Grad" if deg else ""))
    exe = Path(os.environ["QUARTUS_ROOTDIR"]).parent / "qsys" / "bin" / "ip-deploy.exe"
    cmd = [str(exe), "--component-name=altera_iopll", f"--output-name={out.stem}",
           f"--output-directory={out.parent}", "--family=Agilex 5", f"--part={DEVICE}"]
    cmd += [f"--component-parameter={k}={v}" for k, v in params.items()]
    out.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    msgs = [ln for ln in r.stdout.splitlines() + r.stderr.splitlines()
            if "Error" in ln or "Warning" in ln]
    print("\n".join(msgs))
    if r.returncode or any("Error" in ln for ln in msgs) or not out.exists():
        print(r.stdout[-2000:])
        sys.exit("ip-deploy fehlgeschlagen")
    print(f"geschrieben: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
