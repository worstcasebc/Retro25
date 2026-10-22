# linux/system — Systemeinstellungen des Boards (P3a)

Ziel: Ein harter Reset (Hänger bei der Core-Entwicklung, Strom weg) soll das
System auf der SD-Karte nicht mehr beschädigen können. Am 2026-10-16 hatte
eine Serie solcher Resets das Root-Dateisystem zerstört (Superblock,
16 Programme in `/usr/bin`; gerettet mit `tools/sd_rescue.py`).

Prinzip: Das System liegt schreibgeschützt („im Tresor“), beschrieben werden
nur die Datenpartition und RAM-Ordner. Auf eine `ro` eingehängte Partition
schreibt Linux nichts — ein Reset findet dort keinen halben Schreibvorgang.
Ganz ausschließen lässt sich ein Schaden nicht: Der Controller einer SD-Karte
sortiert intern um und kann bei einem Reset mitten im Schreiben in seltenen
Fällen auch benachbarte Daten treffen.

## Aufteilung der SD-Karte

| Partition | Größe | Inhalt | eingehängt |
|---|---|---|---|
| `mmcblk0p1` | 300 MB, FAT | Bootloader, Kernel, Start-Core (`retro25/core.rbf`) | nicht |
| `mmcblk0p2` | 8 GiB, ext4 | Ubuntu (Root) | `/`, **ro** |
| `mmcblk0p3` | 20,8 GiB, ext4, Label `retro25data` | `/media/fat` (Main, Cores, Konfiguration, Spielstände), `/media/fat/retro25` (Bereitstellung, `~/retro25` zeigt dorthin) | `/media/fat`, rw |

Im RAM (nach einem Neustart leer): `/tmp`, `/var/tmp`, `/var/log` (auch das
Journal, höchstens 32 MB), `/var/lib/NetworkManager`,
`/var/lib/systemd/timesync`, `/var/lib/logrotate`, die Datenbanken von
PulseAudio (`~/.config/pulse`) und der jeweils geladene Core
(`/run/retro25-fw/retro25/main.core.rbf`).

## Dateien

| Datei | wohin | Zweck |
|---|---|---|
| `install.sh` | — | installiert alles (schaltet bei Bedarf selbst auf rw und zurück) |
| `fstab` | `/etc/fstab` | Root ro, Datenpartition, RAM-Ordner |
| `tmpfiles-retro25.conf` | `/etc/tmpfiles.d/retro25.conf` | Rechte der RAM-Ordner, Firmware-Suchpfad `/run/retro25-fw` |
| `journald-retro25.conf` | `/etc/systemd/journald.conf.d/` | Journal nur im RAM |
| `90-retro25.conf` | `/etc/sysctl.d/` | Magic SysRq vollständig frei |
| `retro25-rw` | `/usr/local/sbin/retro25-rw`, `retro25-ro` | Root für Wartung umschalten |
| `rw-offen.py` | `/usr/local/sbin/retro25-rw-offen` | zeigt, wer das Root beschreibbar hält |
| `retro25-usb` | `/usr/local/sbin/` | USB-Datenträger ein-/aushängen (`/media/usb0..5`) |
| `retro25-usb@.service` | `/etc/systemd/system/` | je Gerät ein Dienst, an das Gerät gebunden (Abziehen = aushängen) |
| `99-retro25-usb.rules` | `/etc/udev/rules.d/` | startet den Dienst beim Einstecken |

Außerdem schaltet `install.sh` Timer und Dienste ab, die aufs Root schreiben
wollen: apt-Updates, motd-news, man-db, dpkg-db-backup, e2scrub, fstrim,
apport.

## USB-Datenträger (Spiele)

Wie bei MiSTer: Jeder USB-Datenträger mit FAT oder ext4 wird beim Einstecken
unter dem ersten freien `/media/usb0..5` eingehängt (lesen und schreiben,
Besitzer `terasic`, bei FAT mit `flush` — Schreibzugriffe gehen sofort auf den
Stick) und beim Abziehen wieder ausgehängt. exFAT und NTFS kennt der Kernel
nicht. Main sucht Spiele zuerst auf USB (`<Laufwerk>/C64` oder
`<Laufwerk>/games/C64`), dann unter `/media/fat/games/C64`. Einen Stick nie
abziehen, während der Core auf eine Diskette schreibt.
Prüfen: `findmnt | grep usb`, `systemctl status 'retro25-usb@*'`,
`journalctl -u 'retro25-usb@*'`.

## Wartung

```
sudo retro25-rw          # Root beschreibbar (apt, Dateien in /etc …)
sudo retro25-ro          # wieder schreibgeschützt; ein Neustart tut es auch
sudo retro25-rw-offen    # falls retro25-ro "busy" meldet: wer schreibt noch?
```

`linux/main/install.sh` und `linux/system/install.sh` schalten selbst um.
Dateien fürs Board per `scp` nach `~/retro25/` (liegt auf der Datenpartition).

## Hänger: sauber neu starten statt Reset

Solange der Kernel noch Meldungen ausgibt (z. B. `arm-smmu-v3 … CMD_SYNC
timeout`), über die serielle Konsole (COM11, 115200) Magic SysRq senden:
BREAK, dann die Taste — `w`/`l` zur Diagnose, dann `s` (sync), `u` (alles
ro), `b` (Neustart). Nur wenn gar nichts mehr reagiert: Reset-Knopf.

## Netz

Die Ethernet-MAC-Adresse würfelt U-Boot bei jedem Start neu (keine
gespeicherte Adresse); dann vergab der Router jedes Mal eine andere IP.
NetworkManager setzt deshalb eine feste, lokal verwaltete Adresse
(`nmcli con modify "Wired connection 1|2" 802-3-ethernet.cloned-mac-address
a2:d3:33:94:7a:42`, in `/etc/NetworkManager`); das Board ist jetzt immer
unter derselben Adresse erreichbar (zuletzt 192.168.178.125).

## Sicherung

Abbild der ganzen Karte (Karte im PC, Administrator-PowerShell):
`python tools/sd_rescue.py backup DISK F:\retro25-sd\karte.img` —
zurückspielen mit balenaEtcher, Rufus o. Ä.
