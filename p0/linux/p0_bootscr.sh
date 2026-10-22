#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# p0_bootscr.sh — Bootskript von U-Boot für HPS-first erweitern bzw. zurücksetzen.
#
# Aufruf: sudo bash p0_bootscr.sh install <kern.core.rbf> [--no-bridge]
#         sudo bash p0_bootscr.sh restore
#
# install: legt einmalig boot.scr.uimg.orig an, kopiert den Kern als
#          retro25/core.rbf auf die Boot-Partition (FAT) und baut ein
#          Bootskript, das vor "bridge enable" den Kern ins FPGA lädt:
#              load mmc 0:1 ${loadaddr} retro25/core.rbf
#              fpga load 0 ${loadaddr} ${filesize}
#          Im HPS-first-Betrieb ist das FPGA nach dem Einschalten leer —
#          ohne diesen Schritt fände Linux keine Brücke vor.
#          --no-bridge: "bridge enable" auskommentieren — Linux startet mit
#          abgeschalteten Brücken (Versuch: stören aktive Brücken beim Neuladen
#          aus Linux?). Die LW-Bridge ist dann nicht lesbar, nur die LEDs zeigen
#          den Kern; p0_switch.py braucht dafür --no-read.
# restore: stellt boot.scr.uimg.orig wieder her (nötig, bevor wieder das
#          C64-Design im FPGA-first-Betrieb aus dem Flash startet).
#
# Notfall ohne Linux: SD-Karte in den PC, auf der FAT-Partition
# boot.scr.uimg.orig nach boot.scr.uimg kopieren.
# Braucht: mkimage und dumpimage (sudo apt install u-boot-tools).

set -e
CMD=$1
BOOT=/tmp/p0_boot
mkdir -p $BOOT
findmnt $BOOT >/dev/null || mount /dev/mmcblk0p1 $BOOT
trap 'sync; umount $BOOT' EXIT

case "$CMD" in
install)
    RBF=$2
    NOBRIDGE=0
    [ "$3" = "--no-bridge" ] && NOBRIDGE=1
    [ -f "$RBF" ] || { echo "Kern-Datei fehlt: $RBF"; exit 1; }
    command -v mkimage >/dev/null || { echo "mkimage fehlt: sudo apt install u-boot-tools"; exit 1; }
    [ -f $BOOT/boot.scr.uimg.orig ] || cp $BOOT/boot.scr.uimg $BOOT/boot.scr.uimg.orig
    mkdir -p $BOOT/retro25
    cp "$RBF" $BOOT/retro25/core.rbf

    WORK=$(mktemp -d)
    dumpimage -T flat_dt -p 0 -o $WORK/orig.txt $BOOT/boot.scr.uimg.orig >/dev/null
    grep -q "bridge enable" $WORK/orig.txt || { echo "Kein 'bridge enable' im Bootskript — bitte melden:"; cat $WORK/orig.txt; exit 1; }
    # Vor dem ersten "bridge enable" den Kern laden (Einrückung übernehmen).
    awk '!done && /bridge enable/ {
            ind = $0; sub(/[^ \t].*/, "", ind)
            print ind "echo \"Retro25: lade retro25/core.rbf ins FPGA\";"
            print ind "load mmc 0:1 ${loadaddr} retro25/core.rbf;"
            print ind "fpga load 0 ${loadaddr} ${filesize};"
            done = 1
         }
         nob && /bridge enable/ { sub(/bridge enable;/, "echo \"Retro25: Bruecken bleiben aus\";") }
         { print }' nob=$NOBRIDGE $WORK/orig.txt > $WORK/uboot.txt
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
    ;;
restore)
    [ -f $BOOT/boot.scr.uimg.orig ] || { echo "Keine Sicherung boot.scr.uimg.orig vorhanden"; exit 1; }
    cp $BOOT/boot.scr.uimg.orig $BOOT/boot.scr.uimg
    echo "Original-Bootskript wiederhergestellt."
    ;;
*)
    echo "Aufruf: $0 install <kern.core.rbf> | restore"; exit 1
    ;;
esac
