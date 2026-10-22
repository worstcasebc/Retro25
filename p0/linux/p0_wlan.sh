#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# p0_wlan.sh — WLAN-Stick nach einem Core-Wechsel wiederbeleben bzw. schützen.
#
# Hintergrund (P0, Frage 7): Während das FPGA aus Linux neu geladen wird,
# laufen USB-Anfragen an den WLAN-Stick (RT5370, rt2800usb) in
# Zeitüberschreitungen; danach findet er keine Netze mehr. Neu verbinden,
# Neustart von wpa_supplicant/NetworkManager, USB-Reset und Neu-Einstecken
# helfen nicht, nur ein Neustart des Boards.
# ACHTUNG: Den Treiber in diesem Zustand NICHT entladen (modprobe -r
# rt2800usb) — am 2026-10-15 führte das zu einem Kernel-Absturz (Timer des
# entladenen Moduls lief noch). Das Skript fasst den Treiber deshalb nicht an.
#
# Aufruf (als root, über die serielle Konsole — SSH per WLAN reißt ab):
#   sudo bash p0_wlan.sh status
#   sudo bash p0_wlan.sh recover            Leiter ohne Treiberwechsel, jeweils
#                                           bis 30 s auf Verbindung warten
#   sudo bash p0_wlan.sh switch <kern.rbf>  vorbeugend: Funk abschalten
#                                           (nmcli radio wifi off), Kern laden,
#                                           Funk an und verbinden
#
# Gemessen wird jeweils die Zeit bis „verbunden + Router antwortet auf Ping“.

DEV=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}')
CON=$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="802-11-wireless"{print $1; exit}')
HERE=$(cd "$(dirname "$0")" && pwd)

[ -n "$DEV" ] || { echo "Kein WLAN-Gerät gefunden"; exit 1; }
[ -n "$CON" ] || { echo "Keine gespeicherte WLAN-Verbindung gefunden"; exit 1; }
USBPORT=$(basename "$(readlink -f /sys/class/net/$DEV/device/..)")   # z. B. 1-1.1.2

online() {
    # verbunden und das Standard-Gateway antwortet
    nmcli -t -f DEVICE,STATE device | grep -q "^$DEV:connected$" || return 1
    local gw; gw=$(ip route show default dev "$DEV" 2>/dev/null | awk '{print $3; exit}')
    [ -n "$gw" ] && ping -c 1 -W 1 "$gw" >/dev/null 2>&1
}

wait_online() {   # $1 = Sekunden; gibt die benötigte Zeit aus
    local t0=$SECONDS
    while (( SECONDS - t0 < $1 )); do
        online && { echo "  online nach $((SECONDS - t0)) s"; return 0; }
        sleep 1
    done
    echo "  nach $1 s nicht online"; return 1
}

status() {
    echo "Gerät $DEV (USB $USBPORT), Verbindung '$CON'"
    nmcli -t -f DEVICE,STATE,CONNECTION device | grep "^$DEV:"
    echo "Sichtbare Netze: $(nmcli -t -f SSID device wifi list ifname "$DEV" --rescan yes 2>/dev/null | sort -u | grep -c .)"
    online && echo "online" || echo "NICHT online"
}

step() {   # $1 = Beschreibung, Rest = Befehl
    local name=$1; shift
    echo "--- Schritt: $name"
    "$@"
    nmcli connection up "$CON" >/dev/null 2>&1 &
    wait_online 30
}

recover() {
    online && { echo "Schon online — nichts zu tun."; return 0; }
    step "nur neu verbinden" true && return 0
    step "wpa_supplicant + NetworkManager neu starten" \
        systemctl restart wpa_supplicant NetworkManager && return 0
    step "Funk aus und wieder an" \
        bash -c "nmcli radio wifi off; sleep 2; nmcli radio wifi on; sleep 3" && return 0
    # Kein Treiber-Entladen und kein USB-Reset: Beides entfernt die Treiber-
    # Instanz, deren Timer im Fehlerzustand noch läuft (Kernel-Absturz).
    echo "Alle Schritte erfolglos — nur ein Neustart hilft (sudo reboot)."
    return 1
}

switch() {
    local rbf=$1
    [ -f "$rbf" ] || { echo "Kern-Datei fehlt: $rbf"; exit 1; }
    online || echo "Hinweis: WLAN ist schon vorher nicht online."
    echo "--- Funk abschalten"
    nmcli radio wifi off
    sleep 2
    echo "--- Kern laden"
    python3 "$HERE/p0_switch.py" "$rbf" || echo "  Laden meldete einen Fehler"
    echo "--- Funk einschalten und verbinden"
    local t0=$SECONDS
    nmcli radio wifi on
    # NetworkManager verbindet von selbst; nur nachhelfen, wenn das ausbleibt
    # (ein zusätzliches "connection up" würde die frische Verbindung trennen).
    if ! wait_online 10; then
        nmcli connection up "$CON" >/dev/null 2>&1 &
        wait_online 30
    fi && echo "  insgesamt $((SECONDS - t0)) s ab Funk an"
    dmesg | grep -i -E "rt2x00|$DEV" | tail -5
}

case "$1" in
    status)  status ;;
    recover) recover ;;
    switch)  switch "$2" ;;
    *) sed -n '2,20p' "$0"; exit 1 ;;
esac
