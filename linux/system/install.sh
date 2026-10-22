#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Richtet die Systemeinstellungen von Retro25 auf dem Board ein (P3a:
# schreibgeschütztes Root, Daten auf mmcblk0p3, flüchtiges im RAM).
#
# Aufruf im Ordner mit diesem Skript (als root):
#     sudo ./install.sh
# Ist das Root gerade schreibgeschützt, schaltet das Skript selbst auf rw und
# am Ende zurück. Wirksam wird alles vollständig nach einem Neustart.
#
# Legt an bzw. überschreibt:
#   /etc/sysctl.d/90-retro25.conf              SysRq vollständig frei
#   /etc/fstab                                 Root ro, /media/fat auf mmcblk0p3,
#                                              RAM-Ordner (Original einmalig als
#                                              /etc/fstab.vor-retro25)
#   /etc/tmpfiles.d/retro25.conf               Rechte der RAM-Ordner, Firmware-Pfad
#   /etc/systemd/journald.conf.d/retro25.conf  Journal nur im RAM
#   /usr/local/sbin/retro25-rw, retro25-ro     Root für Wartung umschalten
#   /usr/local/sbin/retro25-rw-offen           wer hält das Root beschreibbar?
#   /usr/local/sbin/retro25-usb, /etc/systemd/system/retro25-usb@.service,
#   /etc/udev/rules.d/99-retro25-usb.rules     USB-Datenträger unter /media/usb0..5
#                                              (Einhängepunkte legt das Skript an)
# Schaltet Timer und Dienste ab, die aufs Root schreiben wollen (apt, man-db,
# apport …).

set -e
HERE="$(cd "$(dirname "$0")" && pwd)"

[ "$(id -u)" = 0 ] || { echo "Bitte mit sudo starten."; exit 1; }

if findmnt -no OPTIONS / | tr , '\n' | grep -qx ro; then
	echo "Root ist schreibgeschützt - für die Installation auf rw"
	mount -o remount,rw /
	trap 'sync; mount -o remount,ro / && echo "Root wieder schreibgeschützt"' EXIT
fi

echo "sysctl -> /etc/sysctl.d/90-retro25.conf"
install -m 644 "$HERE/90-retro25.conf" /etc/sysctl.d/90-retro25.conf
sysctl -q -p /etc/sysctl.d/90-retro25.conf

echo "fstab -> /etc/fstab"
[ -e /etc/fstab.vor-retro25 ] || cp -a /etc/fstab /etc/fstab.vor-retro25
install -m 644 "$HERE/fstab" /etc/fstab
if ! blkid -L retro25data >/dev/null; then
	echo "  Hinweis: keine Partition mit Label retro25data - /media/fat bleibt ein Ordner"
fi

echo "tmpfiles -> /etc/tmpfiles.d/retro25.conf"
install -m 644 "$HERE/tmpfiles-retro25.conf" /etc/tmpfiles.d/retro25.conf

echo "journald -> /etc/systemd/journald.conf.d/retro25.conf"
mkdir -p /etc/systemd/journald.conf.d
install -m 644 "$HERE/journald-retro25.conf" /etc/systemd/journald.conf.d/retro25.conf

echo "retro25-rw/-ro -> /usr/local/sbin"
install -m 755 "$HERE/retro25-rw" /usr/local/sbin/retro25-rw
ln -sf retro25-rw /usr/local/sbin/retro25-ro
install -m 755 "$HERE/rw-offen.py" /usr/local/sbin/retro25-rw-offen

echo "USB-Datenträger -> /media/usb0..5 (udev + retro25-usb@.service)"
install -m 755 "$HERE/retro25-usb" /usr/local/sbin/retro25-usb
install -m 644 "$HERE/retro25-usb@.service" /etc/systemd/system/retro25-usb@.service
install -m 644 "$HERE/99-retro25-usb.rules" /etc/udev/rules.d/99-retro25-usb.rules
mkdir -p /media/usb0 /media/usb1 /media/usb2 /media/usb3 /media/usb4 /media/usb5
udevadm control --reload

echo "Timer abschalten, die aufs Root schreiben"
for t in apt-daily.timer apt-daily-upgrade.timer motd-news.timer man-db.timer \
         dpkg-db-backup.timer e2scrub_all.timer fstrim.timer apport-autoreport.timer; do
	if systemctl list-unit-files "$t" >/dev/null 2>&1; then
		systemctl disable --now "$t" >/dev/null 2>&1 || true
		echo "  $t aus"
	fi
done

# Absturzberichte von Ubuntu (apport) brauchen /var/crash auf dem Root
if systemctl list-unit-files apport.service >/dev/null 2>&1; then
	systemctl disable --now apport.service >/dev/null 2>&1 || true
	echo "  apport.service aus"
fi

systemctl daemon-reload
echo "Fertig. Vollständig wirksam nach: sudo reboot"
