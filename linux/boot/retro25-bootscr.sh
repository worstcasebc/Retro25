#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# retro25-bootscr.sh — U-Boot-Bootskript für Retro25 (HPS-first) einrichten.
#
# Aufruf (als root, auf dem Board; braucht u-boot-tools):
#     sudo bash retro25-bootscr.sh install <start.core.rbf>
#     sudo bash retro25-bootscr.sh restore
#     sudo bash retro25-bootscr.sh show          aktuelles Skript anzeigen
#
# install baut aus Terasics Original (boot.scr.uimg.orig, wird beim ersten
# Mal gesichert) ein Skript mit zwei Ergänzungen:
#   1. vor "bridge enable": Start-Core retro25/core.rbf ins FPGA laden
#      (im HPS-first-Betrieb ist das FPGA nach dem Einschalten leer)
#   2. nach dem Laden des Device Tree: DDR-Fenster für das FPGA reservieren
#      (reserved-memory, no-map) — 0xA000_0000–0xBFFF_FFFF, 512 MB. Dort
#      liegen später Scaler-Puffer, Core-Speicher usw.; MiSTer-Adresse
#      0x2000_0000 + Bit 31 = 0xA000_0000 (sys/de25/sysmem_de25.v).
#      no-map: Linux bildet den Bereich gar nicht ab und vergibt ihn nie.
# Analogie: Wir kleben auf die obere Hälfte des Schranks ein Schild
# „gehört dem FPGA“, bevor Linux einzieht und die Fächer verteilt.
#
# Nachfolger von p0/linux/p0_bootscr.sh (dort nur Punkt 1).
# Notfall ohne Linux: SD-Karte in den PC, auf der FAT-Partition
# boot.scr.uimg.orig nach boot.scr.uimg kopieren.

set -e
CMD=$1
BOOT=/tmp/retro25_boot
RESV_NODE=/reserved-memory/retro25_fpga@a0000000
RESV_REG="<0x0 0xa0000000 0x0 0x20000000>"

[ "$(id -u)" = 0 ] || { echo "Bitte mit sudo starten."; exit 1; }
mkdir -p $BOOT
findmnt $BOOT >/dev/null || mount /dev/mmcblk0p1 $BOOT
trap 'sync; umount $BOOT' EXIT

case "$CMD" in
install)
	RBF=$2
	[ -f "$RBF" ] || { echo "Kern-Datei fehlt: $RBF"; exit 1; }
	command -v mkimage >/dev/null || { echo "mkimage fehlt: sudo apt install u-boot-tools"; exit 1; }
	[ -f $BOOT/boot.scr.uimg.orig ] || cp $BOOT/boot.scr.uimg $BOOT/boot.scr.uimg.orig
	mkdir -p $BOOT/retro25
	cp "$RBF" $BOOT/retro25/core.rbf

	WORK=$(mktemp -d)
	dumpimage -T flat_dt -p 0 -o $WORK/orig.txt $BOOT/boot.scr.uimg.orig >/dev/null
	grep -q "bridge enable" $WORK/orig.txt || { echo "Kein 'bridge enable' im Bootskript — bitte melden:"; cat $WORK/orig.txt; exit 1; }
	grep -q "fatload .*fdt_addr_r" $WORK/orig.txt || { echo "Kein 'fatload … fdt_addr_r' im Bootskript — bitte melden:"; cat $WORK/orig.txt; exit 1; }
	awk -v node="$RESV_NODE" -v reg="$RESV_REG" '
		function indent(s) { sub(/[^ \t].*/, "", s); return s }
		!core && /bridge enable/ {
			i = indent($0)
			print i "echo \"Retro25: lade retro25/core.rbf ins FPGA\";"
			print i "load mmc 0:1 ${loadaddr} retro25/core.rbf;"
			print i "fpga load 0 ${loadaddr} ${filesize};"
			core = 1
		}
		{ print }
		!resv && /fatload .*fdt_addr_r/ {
			i = indent($0)
			print i "echo \"Retro25: reserviere 0xA0000000-0xBFFFFFFF fuer das FPGA\";"
			print i "fdt addr ${fdt_addr_r};"
			print i "fdt resize 1024;"
			print i "fdt mknode /reserved-memory " substr(node, length("/reserved-memory/") + 1) ";"
			print i "fdt set " node " reg " reg ";"
			print i "fdt set " node " no-map;"
			# Sonst verschiebt booti den Device Tree ans RAM-Ende (0xBEAxxxxx,
			# mitten ins Fenster) — der Kernel kann das Fenster dann nicht
			# reservieren ("failed to reserve memory"). So bleibt er an der
			# Ladeadresse.
			print i "setenv fdt_high 0xffffffffffffffff;"
			resv = 1
		}' $WORK/orig.txt > $WORK/uboot.txt
	cat > $WORK/uboot_script.its <<'EOF'
/dts-v1/;

/ {
	description = "Retro25 boot script";
	#address-cells = <1>;

	images {
		default = "script";
		script {
			description = "Boot script";
			data = /incbin/("./uboot.txt");
			type = "script";
			compression = "none";
			hash {
				algo = "crc32";
			};
		};
	};
};
EOF
	(cd $WORK && mkimage -f uboot_script.its boot.scr.uimg >/dev/null)
	cp $WORK/boot.scr.uimg $BOOT/boot.scr.uimg
	echo "--- neues Bootskript:"
	cat $WORK/uboot.txt
	rm -rf $WORK
	echo "--- installiert: retro25/core.rbf ($(stat -c %s $BOOT/retro25/core.rbf) Bytes)"
	echo "Nach dem Neustart prüfen: ls /proc/device-tree/reserved-memory/  und  free -m"
	;;
restore)
	[ -f $BOOT/boot.scr.uimg.orig ] || { echo "Keine Sicherung boot.scr.uimg.orig vorhanden"; exit 1; }
	cp $BOOT/boot.scr.uimg.orig $BOOT/boot.scr.uimg
	echo "Original-Bootskript wiederhergestellt."
	;;
show)
	WORK=$(mktemp -d)
	dumpimage -T flat_dt -p 0 -o $WORK/cur.txt $BOOT/boot.scr.uimg >/dev/null
	cat $WORK/cur.txt
	rm -rf $WORK
	;;
*)
	sed -n '4,8p' "$0"; exit 1
	;;
esac
