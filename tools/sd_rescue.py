# SPDX-License-Identifier: GPL-3.0-or-later
"""Root-Partition der SD-Karte unter Windows sichern und reparieren.

Windows kann ext4 nicht prüfen, und der WSL-Kernel von Docker Desktop hat
keinen USB-Speichertreiber. Daher der Umweg über eine Abbild-Datei:

  1. python tools/sd_rescue.py read  DISK  ZIEL.img   (Administrator)
       kopiert Partition 2 (Linux-Root) von \\\\.\\PhysicalDriveDISK in die
       Datei; zusätzlich ZIEL.mbr (erstes MiB) als Sicherung.
  2. e2fsck auf der Datei (Docker, siehe unten) — ändert nur die Datei.
  3. python tools/sd_rescue.py write DISK ZIEL.img [ORIG.img]   (Administrator)
       schreibt nur die 1-MiB-Blöcke zurück, in denen sich ZIEL.img von
       ORIG.img (unveränderte Kopie aus Schritt 1) bzw. ohne ORIG.img vom
       aktuellen Inhalt der Karte unterscheidet. Vorher
       werden alle Windows-Laufwerke dieser Karte gesperrt und abgemeldet.
  python tools/sd_rescue.py info DISK   zeigt nur die Partitionstabelle.
  python tools/sd_rescue.py backup DISK DATEI.img   (Administrator)
       sichert die ganze Karte (alle Partitionen) — zurückspielen auch mit
       balenaEtcher, Rufus o. Ä.

DISK = Nummer aus "Get-CimInstance Win32_DiskDrive" (PHYSICALDRIVE4 -> 4).
Prüfen (Docker):  docker run --rm -v D:/retro25-sd:/sd ubuntu:22.04 e2fsck -fn /sd/p2.img
"""
import ctypes
import ctypes.wintypes as wt
import os
import struct
import sys
import time

CHUNK = 1 << 20
SECTOR = 512


def disk_path(n):
    return rf"\\.\PhysicalDrive{n}"


def partitions(f):
    f.seek(0)
    mbr = f.read(SECTOR)
    if mbr[510:512] != b"\x55\xaa":
        sys.exit("keine MBR-Partitionstabelle gefunden")
    parts = []
    for i in range(4):
        e = mbr[446 + 16 * i: 446 + 16 * (i + 1)]
        ptype = e[4]
        start, count = struct.unpack("<II", e[8:16])
        if ptype:
            parts.append((i + 1, ptype, start * SECTOR, count * SECTOR))
    return parts


def root_part(f):
    parts = partitions(f)
    for no, ptype, ofs, size in parts:
        print(f"Partition {no}: Typ 0x{ptype:02X}, ab {ofs / 2**20:.1f} MiB, {size / 2**30:.2f} GiB")
    p2 = [p for p in parts if p[0] == 2]
    if not p2 or p2[0][1] != 0x83:
        sys.exit("Partition 2 ist keine Linux-Partition (0x83) - falsche Karte?")
    return p2[0][2], p2[0][3]


def progress(done, total, t0):
    dt = max(time.time() - t0, 1e-3)
    print(f"\r  {done / 2**30:6.2f} / {total / 2**30:.2f} GiB, {done / 2**20 / dt:5.1f} MiB/s", end="", flush=True)


def read_robust(f, pos, n_bytes, bad):
    """Liest n_bytes ab pos; unlesbare Sektoren werden 0 und landen in bad."""
    for _ in range(3):
        try:
            f.seek(pos)
            return f.read(n_bytes)
        except OSError:
            time.sleep(0.2)
    # einzeln in 4-KiB- bzw. Sektor-Stücken
    out = bytearray()
    step = 4096
    p = pos
    while p < pos + n_bytes:
        try:
            f.seek(p)
            out += f.read(step)
            p += step
        except OSError:
            if step > SECTOR:
                step = SECTOR
                continue
            out += bytes(SECTOR)
            bad.append(p)
            p += SECTOR
            if (p - pos) % 4096 == 0:
                step = 4096
    return bytes(out)


def cmd_read(n, dst):
    handles = lock_volumes(n)
    try:
        with open(disk_path(n), "rb", buffering=0) as f:
            ofs, size = root_part(f)
            mbr = dst[:-4] + ".mbr" if dst.endswith(".img") else dst + ".mbr"
            with open(mbr, "wb") as m:
                m.write(read_robust(f, 0, CHUNK, []))
            # angefangene Datei fortsetzen
            done = 0
            if os.path.exists(dst):
                done = (os.path.getsize(dst) // CHUNK) * CHUNK
                print(f"setze bei {done / 2**30:.2f} GiB fort")
            bad = []
            t0 = time.time()
            start = done
            with open(dst, "r+b" if done else "wb") as o:
                o.seek(done)
                o.truncate()
                while done < size:
                    n_bytes = min(CHUNK, size - done)
                    o.write(read_robust(f, ofs + done, n_bytes, bad))
                    done += n_bytes
                    if done % (64 * CHUNK) == 0 or done == size:
                        dt = max(time.time() - t0, 1e-3)
                        print(f"\r  {done / 2**30:6.2f} / {size / 2**30:.2f} GiB, "
                              f"{(done - start) / 2**20 / dt:5.1f} MiB/s, unlesbar: {len(bad)} Sektoren",
                              end="", flush=True)
            if bad:
                with open(dst + ".bad", "a") as b:
                    for p in bad:
                        b.write(f"{(p - ofs) // SECTOR}\n")   # Sektor relativ zur Partition
        print(f"\nfertig: {dst}" +(f", {len(bad)} unlesbare Sektoren in {dst}.bad" if bad else ""))
    finally:
        for hv in handles:
            k32.CloseHandle(hv)


# --- Windows-Laufwerke der Karte sperren (sonst verweigert Windows das Schreiben)
k32 = ctypes.WinDLL("kernel32", use_last_error=True)
# Typen angeben: Handles sind 64 bit, ohne Angabe kürzt ctypes sie auf int
k32.CreateFileW.restype = wt.HANDLE
k32.CreateFileW.argtypes = [wt.LPCWSTR, wt.DWORD, wt.DWORD, wt.LPVOID, wt.DWORD, wt.DWORD, wt.HANDLE]
k32.FindFirstVolumeW.restype = wt.HANDLE
k32.FindFirstVolumeW.argtypes = [wt.LPWSTR, wt.DWORD]
k32.FindNextVolumeW.restype = wt.BOOL
k32.FindNextVolumeW.argtypes = [wt.HANDLE, wt.LPWSTR, wt.DWORD]
k32.FindVolumeClose.argtypes = [wt.HANDLE]
k32.CloseHandle.argtypes = [wt.HANDLE]
k32.DeviceIoControl.restype = wt.BOOL
k32.DeviceIoControl.argtypes = [wt.HANDLE, wt.DWORD, wt.LPVOID, wt.DWORD, wt.LPVOID, wt.DWORD,
                                ctypes.POINTER(wt.DWORD), wt.LPVOID]
INVALID = wt.HANDLE(-1).value
IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS = 0x00560000
FSCTL_LOCK_VOLUME = 0x00090018
FSCTL_DISMOUNT_VOLUME = 0x00090020


def volumes_on_disk(n):
    buf = ctypes.create_unicode_buffer(260)
    h = k32.FindFirstVolumeW(buf, 260)
    vols = []
    if h == INVALID:
        return vols
    try:
        while True:
            name = buf.value.rstrip("\\")
            hv = k32.CreateFileW(name, 0, 3, None, 3, 0, None)
            if hv != INVALID:
                out = ctypes.create_string_buffer(256)
                ret = wt.DWORD()
                if k32.DeviceIoControl(hv, IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS, None, 0,
                                       out, 256, ctypes.byref(ret), None):
                    cnt = struct.unpack_from("<I", out.raw, 0)[0]
                    for i in range(cnt):
                        disk = struct.unpack_from("<I", out.raw, 8 + 24 * i)[0]
                        if disk == n:
                            vols.append(name)
                k32.CloseHandle(hv)
            if not k32.FindNextVolumeW(h, buf, 260):
                break
    finally:
        k32.FindVolumeClose(h)
    return vols


def lock_volumes(n):
    handles = []
    for name in volumes_on_disk(n):
        hv = k32.CreateFileW(name, 0xC0000000, 3, None, 3, 0, None)
        if hv == INVALID:
            sys.exit(f"Laufwerk {name} nicht zu öffnen (Fehler {ctypes.get_last_error()})")
        ret = wt.DWORD()
        if not k32.DeviceIoControl(hv, FSCTL_LOCK_VOLUME, None, 0, None, 0, ctypes.byref(ret), None):
            sys.exit(f"Laufwerk {name} nicht zu sperren (in Benutzung? Fehler {ctypes.get_last_error()})")
        k32.DeviceIoControl(hv, FSCTL_DISMOUNT_VOLUME, None, 0, None, 0, ctypes.byref(ret), None)
        print(f"gesperrt: {name}")
        handles.append(hv)
    return handles


def cmd_write(n, fixed, orig=None):
    """Schreibt die Blöcke von fixed, die sich von orig unterscheiden. Ohne
    orig wird mit dem aktuellen Inhalt der Karte verglichen (langsamer)."""
    size = os.path.getsize(fixed)
    if orig and os.path.getsize(orig) != size:
        sys.exit("Abbilder sind verschieden groß")
    handles = lock_volumes(n)
    try:
        with open(disk_path(n), "r+b", buffering=0) as f:
            ofs, psize = root_part(f)
            # kleiner ist erlaubt: nach resize2fs belegt das Dateisystem nur
            # noch den Anfang der Partition
            if size > psize:
                sys.exit("Abbild größer als die Partition")
            if size < psize:
                print(f"Abbild ({size / 2**30:.2f} GiB) kleiner als die Partition: nur der Anfang wird verglichen")
            t0 = time.time()
            done = written = 0
            b = open(orig, "rb") if orig else None
            with open(fixed, "rb") as a:
                while done < size:
                    da = a.read(CHUNK)
                    if b:
                        db = b.read(CHUNK)
                    else:
                        f.seek(ofs + done)
                        db = f.read(len(da))
                    if da != db:
                        f.seek(ofs + done)
                        f.write(da)
                        written += 1
                    done += len(da)
                    if done % (64 * CHUNK) == 0 or done == size:
                        progress(done, size, t0)
                        print(f", geschrieben {written} MiB", end="", flush=True)
            if b:
                b.close()
            print(f"\n{written} MiB-Blöcke zurückgeschrieben")
    finally:
        for hv in handles:
            k32.CloseHandle(hv)


def disk_size(n):
    """Größe des Datenträgers in Byte (IOCTL_DISK_GET_LENGTH_INFO)."""
    h = k32.CreateFileW(disk_path(n), 0x80000000, 3, None, 3, 0, None)
    if h == INVALID:
        sys.exit(f"Datenträger {n} nicht zu öffnen (Fehler {ctypes.get_last_error()})")
    out = ctypes.c_longlong()
    ret = wt.DWORD()
    ok = k32.DeviceIoControl(h, 0x0007405C, None, 0, ctypes.byref(out), 8, ctypes.byref(ret), None)
    k32.CloseHandle(h)
    if not ok:
        sys.exit(f"Größe von Datenträger {n} nicht lesbar (Fehler {ctypes.get_last_error()})")
    return out.value


def cmd_backup(n, dst):
    size = disk_size(n)
    handles = lock_volumes(n)
    try:
        with open(disk_path(n), "rb", buffering=0) as f:
            root_part(f)   # nur zur Kontrolle: richtige Karte?
            print(f"Karte: {size / 2**30:.2f} GiB")
            bad = []
            t0 = time.time()
            done = 0
            with open(dst, "wb") as o:
                while done < size:
                    n_bytes = min(CHUNK, size - done)
                    o.write(read_robust(f, done, n_bytes, bad))
                    done += n_bytes
                    if done % (64 * CHUNK) == 0 or done == size:
                        progress(done, size, t0)
            print(f"\nfertig: {dst}" + (f", {len(bad)} unlesbare Sektoren" if bad else ""))
    finally:
        for hv in handles:
            k32.CloseHandle(hv)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    cmd, n = sys.argv[1], int(sys.argv[2])
    if cmd == "info":
        with open(disk_path(n), "rb", buffering=0) as f:
            root_part(f)
    elif cmd == "backup" and len(sys.argv) == 4:
        cmd_backup(n, sys.argv[3])
    elif cmd == "read" and len(sys.argv) == 4:
        cmd_read(n, sys.argv[3])
    elif cmd == "write" and len(sys.argv) in (4, 5):
        cmd_write(n, sys.argv[3], sys.argv[4] if len(sys.argv) == 5 else None)
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
