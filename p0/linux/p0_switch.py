#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Lädt Kerne (.core.rbf) zur Laufzeit ins FPGA und prüft sie — P0-Versuch.

Aufruf (als root, im Ordner mit den .core.rbf):
    sudo python3 p0_switch.py p0_b.core.rbf               einen Kern laden
    sudo python3 p0_switch.py --loop 20 p0_a.core.rbf p0_b.core.rbf p0_c.core.rbf
    sudo python3 p0_switch.py --read                       nur Register lesen
    sudo python3 p0_switch.py --no-read p0_b.core.rbf      laden, Brücke nicht anfassen
                                                           (Boot mit p0_bootscr.sh --no-bridge)

Ablauf je Kern:
 1. Kern nach /lib/firmware/retro25/ kopieren.
 2. Ein Device-Tree-Overlay auf /fpga-region anwenden, dessen firmware-name
    auf den Kern zeigt (configfs). Der Kernel-Treiber des FPGA-Managers schickt
    den Kern dann über das SDM ins FPGA. Ein altes Overlay wird vorher entfernt.
 3. Warten, bis der FPGA-Manager "operating" meldet — erst dann ist das
    Fabric wieder da. Ein Zugriff auf die Brücke vorher kann Linux mit einem
    SError abstürzen lassen.
 4. Über die LW-Bridge die Register von p0_regs lesen: ID ("R25A/B/C"),
    SCRATCH schreiben und zurücklesen, UPTIME (klein = frisch geladen).

Voraussetzungen: Dienst c64d gestoppt (er greift sonst auf die Brücke zu),
dtc installiert (sudo apt install device-tree-compiler).
"""
import argparse
import mmap
import os
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path

FW_DIR = Path("/lib/firmware/retro25")
OVERLAY_DIR = Path("/sys/kernel/config/device-tree/overlays/retro25")
FPGA_MGR = Path("/sys/class/fpga_manager/fpga0")
MODULES = ["stratix10-soc", "of-fpga-region"]

LW_BASE = 0x2001_0000          # Fenster der Brücken im LW-Bridge-Bereich
REG_CORE = 0x100               # p0_regs an c64_m0
REG_DISK = 0x4000              # p0_regs an disk_m0
IDS = {0x52323541: "R25A", 0x52323542: "R25B", 0x52323543: "R25C", 0x5232352D: "R25-"}

OVERLAY_DTS = """/dts-v1/;
/plugin/;

/ {{
	fragment@0 {{
		target-path = "/fpga-region";
		__overlay__ {{
			firmware-name = "retro25/{fw}";
			config-complete-timeout-us = <30000000>;
		}};
	}};
}};
"""


def sh(*cmd: str, check: bool = True) -> str:
    r = subprocess.run(cmd, capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"Fehler bei {' '.join(cmd)}:\n{r.stdout}{r.stderr}")
    return r.stdout.strip()


def preflight() -> None:
    if os.geteuid() != 0:
        sys.exit("Bitte mit sudo starten.")
    if subprocess.run(["systemctl", "is-active", "--quiet", "c64d"]).returncode == 0:
        sys.exit("Der Dienst c64d läuft und greift auf die Brücke zu: sudo systemctl stop c64d")
    if not shutil.which("dtc"):
        sys.exit("dtc fehlt: sudo apt install device-tree-compiler")
    for m in MODULES:
        sh("modprobe", m)
    if not FPGA_MGR.exists():
        sys.exit(f"{FPGA_MGR} fehlt — FPGA-Manager-Treiber nicht geladen?")


def mgr_state() -> str:
    return (FPGA_MGR / "state").read_text().strip()


def read_regs(base: int) -> dict:
    fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    try:
        m = mmap.mmap(fd, 0x8000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=LW_BASE)
        rd = lambda off: struct.unpack_from("<I", m, base + off)[0]
        wr = lambda off, v: struct.pack_into("<I", m, base + off, v)
        regs = {"id": rd(0x0), "uptime": rd(0x8), "status": rd(0xC)}
        pattern = int(time.time()) & 0xFFFFFFFF ^ 0xA5A5_0000
        wr(0x4, pattern)
        regs["scratch_ok"] = rd(0x4) == pattern
        m.close()
        return regs
    finally:
        os.close(fd)


def show(label: str) -> dict:
    regs = read_regs(REG_CORE)
    disk = read_regs(REG_DISK)
    print(f"  {label}: ID {IDS.get(regs['id'], hex(regs['id']))}, "
          f"Uptime {regs['uptime'] / 100e6:.2f} s, Status 0x{regs['status']:02x}, "
          f"Scratch {'ok' if regs['scratch_ok'] else 'FALSCH'}, "
          f"disk_m0 {IDS.get(disk['id'], hex(disk['id']))}")
    return regs


def load(rbf: Path) -> float:
    """Lädt einen Kern; gibt die Ladezeit in Sekunden zurück."""
    FW_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(rbf, FW_DIR / rbf.name)
    dts = FW_DIR / "overlay.dts"
    dtbo = FW_DIR / f"{rbf.stem}.dtbo"
    dts.write_text(OVERLAY_DTS.format(fw=rbf.name))
    sh("dtc", "-q", "-@", "-I", "dts", "-O", "dtb", "-o", str(dtbo), str(dts))

    if OVERLAY_DIR.exists():
        OVERLAY_DIR.rmdir()          # altes Overlay entfernen (lädt nichts)
    OVERLAY_DIR.mkdir()
    t0 = time.monotonic()
    (OVERLAY_DIR / "path").write_text(f"retro25/{dtbo.name}")   # blockiert, bis geladen
    dt = time.monotonic() - t0
    status = (OVERLAY_DIR / "status").read_text().strip()
    state = mgr_state()
    if status != "applied" or state != "operating":
        print(f"  FEHLER: Overlay {status}, FPGA-Manager {state}")
        print("\n".join(sh("dmesg", check=False).splitlines()[-15:]))
        sys.exit(1)
    return dt


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("rbf", nargs="*", type=Path, help="Kerne (.core.rbf)")
    ap.add_argument("--loop", type=int, default=1, help="so oft alle Kerne nacheinander laden")
    ap.add_argument("--read", action="store_true", help="nur Register lesen")
    ap.add_argument("--no-read", action="store_true",
                    help="Brücke nicht lesen (Brücken abgeschaltet), nur Laden prüfen")
    args = ap.parse_args()

    preflight()
    print(f"FPGA-Manager: {sh('cat', str(FPGA_MGR / 'name'))}, Zustand {mgr_state()}")
    if args.read or not args.rbf:
        if mgr_state() == "operating":
            show("jetzt")
        else:
            print("FPGA nicht im Betrieb — Brücke wird nicht gelesen.")
        return 0

    errors = 0
    for n in range(args.loop):
        for rbf in args.rbf:
            print(f"[{n + 1}/{args.loop}] lade {rbf.name} ...", flush=True)
            dt = load(rbf)
            if args.no_read:
                print(f"  geladen in {dt:.2f} s (Brücke nicht gelesen, LEDs prüfen)")
                continue
            regs = show(f"[{n + 1}/{args.loop}] {rbf.name} in {dt:.2f} s")
            want = "R25" + rbf.name.split(".")[0][-1].upper()
            if IDS.get(regs["id"]) != want or not regs["scratch_ok"]:
                print(f"  FEHLER: erwartet {want}")
                errors += 1
    print(f"\nFertig: {args.loop * len(args.rbf)} Ladevorgänge, {errors} Fehler.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
