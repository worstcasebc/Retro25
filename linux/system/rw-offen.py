#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""rw-offen.py — zeigt, welche Prozesse Dateien auf dem Root zum Schreiben
offen halten oder beschreibbar eingeblendet haben (mmap) — deshalb schlägt
"retro25-ro" fehl ("mount point is busy"). Ersatz für fuser/lsof, die im
Terasic-Image fehlen. Installiert als /usr/local/sbin/retro25-rw-offen.

Aufruf:  sudo retro25-rw-offen
"""
import os

# Pseudo-Dateien; alles andere entscheidet das Gerät (st_dev == Root)
SKIP = ("/proc/", "/dev/", "/sys/")


def on_root(path, root_dev):
    try:
        return os.stat(path).st_dev == root_dev
    except OSError:
        return False


def main():
    root_dev = os.stat("/").st_dev
    found = set()
    for pid in filter(str.isdigit, os.listdir("/proc")):
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
            comm = open(f"/proc/{pid}/comm").read().strip()
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
                flags = 0
                for line in open(f"/proc/{pid}/fdinfo/{fd}"):
                    if line.startswith("flags:"):
                        flags = int(line.split()[1], 8)
                st = os.stat(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if not target.startswith("/") or target.startswith(SKIP):
                continue
            if st.st_dev != root_dev:
                continue
            if flags & 3:   # O_WRONLY oder O_RDWR
                found.add(f"{comm} (PID {pid}): {target}")
        # beschreibbar und geteilt eingeblendete Dateien (z. B. Datenbanken)
        try:
            maps = open(f"/proc/{pid}/maps").read().splitlines()
        except OSError:
            continue
        for line in maps:
            parts = line.split(None, 5)
            if len(parts) == 6 and parts[1].startswith("rw") and parts[1][3] == "s":
                path = parts[5]
                if path.startswith("/") and not path.startswith(SKIP) and on_root(path, root_dev):
                    found.add(f"{comm} (PID {pid}): {path} (mmap)")
    for line in sorted(found):
        print(line)
    if not found:
        print("keine Datei auf / zum Schreiben offen")


if __name__ == "__main__":
    main()
