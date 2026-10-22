#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Richtet Main_MiSTer auf dem DE25-Nano ein (als root, auf dem Board).
#
# Aufruf im Ordner mit diesem Skript (dort liegen auch board/, MiSTer.ini
# und das fertige Programm MiSTer):
#     sudo ./install.sh [Core.rbf ...]
#
# Legt an bzw. überschreibt:
#   /media/fat/MiSTer                     das Programm (MiSTer-Ordnerstruktur)
#   /media/fat/MiSTer.ini                 nur, wenn noch keine da ist
#   /media/fat/_Retro25/<Core>.rbf        die angegebenen Cores (menu: /media/fat/menu.rbf)
#   /media/fat/games/C64                  Spiele/Disketten (Besitzer terasic)
#   /lib/firmware/retro25/main.dtbo       Overlay zum Core-Laden
#   /usr/local/bin/retro25-switch-hook    WLAN beim Core-Wechsel aus/ein
#   /etc/modules-load.d/retro25.conf      FPGA-Manager-Module beim Booten laden
#   /etc/systemd/system/retro25-main.service  Main beim Booten starten
#   /etc/default/retro25                  Start-Core für Main, nur wenn noch
#                                         keine da ist (erster angegebener Core)
# /media/fat ist (vorerst) ein normaler Ordner auf der Linux-Partition.

set -e
HERE="$(cd "$(dirname "$0")" && pwd)"

[ "$(id -u)" = 0 ] || { echo "Bitte mit sudo starten."; exit 1; }
command -v dtc >/dev/null || { echo "dtc fehlt: sudo apt install device-tree-compiler"; exit 1; }
[ -x "$HERE/MiSTer" ] || { echo "$HERE/MiSTer fehlt (erst bauen: build.sh)"; exit 1; }

# Root schreibgeschützt (P3a, linux/system)? Dann für die Installation auf rw
# und am Ende zurück.
if findmnt -no OPTIONS / | tr , '\n' | grep -qx ro; then
	echo "Root ist schreibgeschützt - für die Installation auf rw"
	mount -o remount,rw /
	trap 'sync; mount -o remount,ro / && echo "Root wieder schreibgeschützt"' EXIT
fi

echo "Module des FPGA-Managers"
printf 'stratix10-soc\nof-fpga-region\n' > /etc/modules-load.d/retro25.conf
modprobe stratix10-soc
modprobe of-fpga-region

echo "Overlay -> /lib/firmware/retro25/main.dtbo"
mkdir -p /lib/firmware/retro25
dtc -q -@ -I dts -O dtb -o /lib/firmware/retro25/main.dtbo "$HERE/board/retro25-main.dts"
# Den Core legt Main seit P3a in /run ab; eine alte Kopie hier stört nur.
rm -f /lib/firmware/retro25/main.core.rbf

echo "Hook -> /usr/local/bin/retro25-switch-hook"
install -m 755 "$HERE/board/retro25-switch-hook" /usr/local/bin/retro25-switch-hook

echo "Programm -> /media/fat/MiSTer"
mkdir -p /media/fat/config /media/fat/_Retro25
# Spiele/Disketten wie bei MiSTer unter games/<Core>; dem Nutzer terasic,
# damit Dateien ohne sudo hineinkopiert werden können (auch _Retro25: Testcores)
mkdir -p /media/fat/games/C64
chown -R terasic:terasic /media/fat/games /media/fat/_Retro25
# Läuft Main gerade, ist die Datei belegt: erst beenden (Dienst und von Hand
# gestartete Instanzen).
systemctl stop retro25-main 2>/dev/null || true
if pgrep -x MiSTer >/dev/null; then pkill -x MiSTer; sleep 0.5; fi
install -m 755 "$HERE/MiSTer" /media/fat/MiSTer
[ -e /media/fat/MiSTer.ini ] || install -m 644 "$HERE/MiSTer.ini" /media/fat/MiSTer.ini
# Die HDMI-PLL ist (bis P3 Schritt 4) fest auf 74,25 MHz = Modus 0
# (1280x720@60). Ohne video_mode fragte Main die EDID des Monitors ab — über
# den I2C des HPS, an dem der HDMI-Sender beim DE25 nicht hängt. Daher die
# auskommentierte Vorgabezeile aktivieren, falls kein Modus gesetzt ist.
if ! grep -q '^video_mode=' /media/fat/MiSTer.ini; then
	echo "MiSTer.ini: video_mode=0 (1280x720@60, passend zur festen HDMI-PLL)"
	sed -i '0,/^;video_mode=0/s//video_mode=0/' /media/fat/MiSTer.ini
fi

first=""
for rbf in "$@"; do
	name="$(basename "$rbf")"
	name="${name%.core.rbf}"
	name="${name%.rbf}"
	# Erster Buchstabe groß, wie bei MiSTer-Cores üblich (testpattern -> Testpattern);
	# der Menü-Core liegt wie bei MiSTer als menu.rbf in der Wurzel
	if [ "${name,,}" = menu ]; then
		dst="/media/fat/menu.rbf"
	else
		dst="/media/fat/_Retro25/${name^}.rbf"
	fi
	echo "Core $rbf -> $dst"
	install -m 644 "$rbf" "$dst"
	# Start-Core = erster angegebener; das Menü bekommt Main ohne Pfad (wie bei MiSTer)
	if [ -z "$first_done" ]; then
		first_done=1
		[ "$dst" = /media/fat/menu.rbf ] || first="$dst"
	fi
done

# Start-Core: muss zu dem Kern passen, den U-Boot lädt (retro25/core.rbf auf
# der Boot-Partition). Eine vorhandene Datei bleibt unangetastet.
if [ ! -e /etc/default/retro25 ]; then
	echo "Start-Core -> /etc/default/retro25 (${first:-keiner})"
	cat > /etc/default/retro25 <<EOT
# Pfad des Cores, den U-Boot beim Booten lädt — Main bekommt ihn als
# Argument (retro25-main.service). Leer: Main startet ohne Core-Pfad.
RETRO25_CORE=$first
EOT
fi

echo "Dienst -> /etc/systemd/system/retro25-main.service"
install -m 644 "$HERE/board/retro25-main.service" /etc/systemd/system/retro25-main.service
systemctl daemon-reload
systemctl enable retro25-main
systemctl restart retro25-main

echo "Fertig. Main läuft als Dienst (Core muss geladen sein, z. B. per U-Boot):"
echo "    systemctl status retro25-main       journalctl -u retro25-main -f"
echo "Von Hand starten: erst  sudo systemctl stop retro25-main"
