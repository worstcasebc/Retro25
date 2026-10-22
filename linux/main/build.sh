#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Baut Main_MiSTer für das DE25-Nano (aarch64).
#
# Aufruf (auf dem Board oder im arm64-Container, aus linux/main/):
#     ./build.sh            Quellbaum neu anlegen und bauen
#     ./build.sh DEBUG=1    zusätzliche make-Variablen werden durchgereicht
# Ergebnis: build/src/bin/MiSTer
#
# Ablauf — wie bei sys/de25: Fremdcode bleibt unverändert, Änderungen liegen
# daneben und werden erst beim Bauen eingemischt.
#   1. linux/vendor/main_mister nach build/src kopieren
#   2. kleine Korrekturen aus patches/*.patch anwenden (in Namensreihenfolge)
#   3. Ersatzdateien aus de25/ darüberkopieren (ganz neu geschriebene Teile,
#      z. B. fpga_io.cpp)
#   4. make mit linux/main/Makefile
# Ein zweiter Aufruf baut nur, was sich geändert hat (cmp vergleicht
# Inhalte, unveränderte Dateien behalten ihren Zeitstempel). Gelöschte
# Dateien bleiben im Bauordner liegen — dann build/ von Hand löschen.

set -e
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VENDOR="$HERE/../vendor/main_mister"
SRC="$HERE/build/src"
STAGE="$HERE/build/stage"

rm -rf "$STAGE"
mkdir -p "$STAGE" "$SRC"
cp -r "$VENDOR/." "$STAGE/"

for p in "$HERE"/patches/*.patch; do
	[ -e "$p" ] || continue
	echo "Patch: $(basename "$p")"
	patch -s -p1 -d "$STAGE" < "$p"
done

cp -r "$HERE/de25/." "$STAGE/"

# Nur geänderte Dateien in den Bauordner übernehmen (spart Neuübersetzen)
(cd "$STAGE" && find . -type f) | while read -r f; do
	if ! cmp -s "$STAGE/$f" "$SRC/$f"; then
		mkdir -p "$(dirname "$SRC/$f")"
		cp -p "$STAGE/$f" "$SRC/$f"
	fi
done
rm -rf "$STAGE"

make -C "$SRC" -f "$HERE/Makefile" "$@"
ls -l "$SRC/bin/MiSTer"
