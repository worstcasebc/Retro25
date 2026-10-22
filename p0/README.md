# P0 — Core-Wechsel aus Linux (Machbarkeit)

Ziel: zeigen, dass Linux das FPGA des DE25-Nano im laufenden Betrieb mit
verschiedenen Kernen laden kann, bevor Arbeit in den MiSTer-Port fließt
(siehe [docs/roadmap.md](../docs/roadmap.md)).

Analogie: Bisher (C64) ist das FPGA wie eine fest eingebaute Platine — das
Flash enthält alles, und es startet vor Linux. Für MiSTer-Betrieb wird es zum
Steckplatz: Das Flash enthält nur noch den „Rahmen“ (I/O-Ring + Bootloader des
HPS, **HPS-first**), und den „Einschub“ (Kern, `.core.rbf`) steckt erst U-Boot
und später Linux hinein — und jederzeit einen anderen.

## Was gebaut wird

Ein Quartus-Projekt `quartus/p0.qpf` mit drei Revisionen. Alle haben
dieselben Pins und dasselbe HPS-System (aus dem C64-Projekt, mit den Brücken
`c64_m0`/`disk_m0`):

| Revision | LEDR[3:0] | LEDR[7] | Besonderheit | ID |
|---|---|---|---|---|
| `p0_a` | Lauflicht | Herzschlag aus CLOCK0_50 | — | `R25A` |
| `p0_b` | blinken gemeinsam 2 Hz | Herzschlag aus CLOCK0_50 | nur andere Logik | `R25B` |
| `p0_c` | Binärzähler | Herzschlag aus PLL | eigene PLL `pll_c64` | `R25C` |

Register für Linux (`rtl/p0_regs.v`, Testbench `tb/tb_p0_regs.v`), Basis der
LW-Bridge `0x2000_0000`:

| Adresse | Register |
|---|---|
| `0x2001_0100` | ID (`R25A`/`B`/`C`) |
| `0x2001_0104` | SCRATCH (lesen/schreiben) |
| `0x2001_0108` | UPTIME (100-MHz-Takte seit Reset → klein = frisch geladen) |
| `0x2001_010C` | STATUS: Bit 3..0 SW, Bit 5..4 KEY (1 = gedrückt) |
| `0x2001_4000` | gleiches Registerset, ID `R25-` |

## Fragen, die P0 beantwortet

1. Lässt sich ein Kern wiederholt und abwechselnd laden (≥ 20 Mal)?
2. Ändert eine eigene PLL (Revision C) die Prüfsummen `IO hash` / `HPS IO hash`?
   Wenn ja, darf ein Kern keine eigene PLL mitbringen.
3. Bleibt die LW-Bridge nach dem Laden nutzbar?
4. Ist `/dev/mem` erlaubt, wo liegt das DDR (`/proc/iomem`)?
5. Kennt Terasics U-Boot `fpga load`?
6. Funktioniert `sudo reboot`? Im FPGA-first-Betrieb (C64) fährt Linux sauber
   herunter, aber der Hardware-Neustart bleibt hängen (beobachtet 2026-10-15,
   letzte Meldung „systemd-shutdown: Sending SIGTERM“, Watchdog auf 10 min).
   Main_MiSTer startet bei manchen Aktionen neu — im HPS-first-Betrieb prüfen.
7. Übersteht USB (WLAN-Stick, Tastatur, Gamepads) das Umladen? (Erst beim
   Versuch aufgefallen.)

## Ablauf

### Schritt 1 — Vorprüfung auf dem Board (heute möglich, ändert nichts)

Mit dem jetzigen C64-Setup. Dateien aufs Board kopieren (Board-IP anpassen;
Windows bringt `scp` mit):

```
scp p0\linux\* terasic@<board-ip>:~/p0/
```

Auf dem Board:

```
sudo systemctl stop c64d
sudo systemctl disable c64d          # bis P0 vorbei ist
sudo apt install device-tree-compiler u-boot-tools
cd ~/p0
sudo bash p0_check.sh | tee p0_check.txt
```

`p0_check.txt` bitte komplett zurückgeben. Bei „FEHLT“ für die Module oder
ohne `fpga load` in U-Boot geht es mit Schritt 3 erst nach Klärung weiter.

### Schritt 2 — Bauen (PC)

```
subst Q: <Pfad zu Retro25>
python tools\fetch_hps.py          (einmalig; damals aus C64-DE25 — heute: Terasics GHRD als Quelle angeben, siehe README.md)
Q:\p0\quartus\build_p0.bat
```

`build_p0.bat` baut alle drei Revisionen und ruft `quartus_pfg` mit
`-o hps=1` auf. Ergebnis in `p0\quartus\output_files\`: `p0_a.hps.jic`
(fürs Flash) und `p0_a/b/c.core.rbf`. Am Ende zeigt es die Prüfsummen —
damit ist **Frage 2 schon beantwortet**, bevor das Board ins Spiel kommt.
Bitte die Zeilen mit „hash“ zurückgeben.

Falls Quartus über ungenerierte IP klagt: Projekt einmal in der GUI öffnen
(`Q:\p0\quartus\p0.qpf`), Platform Designer `qsys_top.qsys` → *Generate HDL*.

### Schritt 3 — Bootskript erweitern (Board)

```
scp p0\quartus\output_files\p0_*.core.rbf terasic@<board-ip>:~/p0/
```

Auf dem Board:

```
cd ~/p0
sudo bash p0_bootscr.sh install p0_a.core.rbf
sudo poweroff
```

Das Skript sichert das Original als `boot.scr.uimg.orig` und lässt U-Boot vor
`bridge enable` den Kern `retro25/core.rbf` laden.

### Schritt 4 — HPS-first ins Flash (PC)

SW5 in den AS-Modus (SW5.1 OFF, SW5.2 und SW5.3 ON, nur stromlos), Board an,
dann `Q:\p0\quartus\flash_p0.bat`. Danach aus- und wieder einschalten.

Erwartet: Am HPS-UART (COM11, 115200) erscheint
`Retro25: lade retro25/core.rbf ins FPGA`, LEDR[3:0] zeigen das Lauflicht,
LEDR[7] blinkt, Linux bootet wie gewohnt.

### Schritt 5 — Kerne wechseln (Board)

```
cd ~/p0
sudo python3 p0_switch.py --read
sudo python3 p0_switch.py p0_b.core.rbf
sudo python3 p0_switch.py p0_c.core.rbf
sudo python3 p0_switch.py --loop 20 p0_a.core.rbf p0_b.core.rbf p0_c.core.rbf
```

Erwartet: LEDs wechseln das Muster, ID passt zum Kern, Scratch „ok“,
Uptime jeweils nur Sekundenbruchteile. Ausgabe und ggf. `dmesg | tail -30`
bitte zurückgeben.

## Zurück zum C64

```
sudo bash ~/p0/p0_bootscr.sh restore
sudo systemctl enable --now c64d
```

Dann `C64-DE25\quartus_hps\flash_program.bat` (SW5 im AS-Modus), aus- und
einschalten.

**Notfall** (Linux startet nicht mehr): SD-Karte in den PC, auf der
FAT-Partition `boot.scr.uimg.orig` nach `boot.scr.uimg` kopieren. Das Flash
lässt sich immer per JTAG neu beschreiben (`flash_program.bat`), notfalls mit
Terasics `golden_top_hps.jic`.

## Ergebnisse

| Frage | Ergebnis |
|---|---|
| 1 Wiederholtes Laden | **Ja.** 2026-10-15 über die serielle Konsole: 21 Ladevorgänge (A↔B, `--loop 10`), 0 Fehler, je **2,13 s**; Brücken dabei aktiv (`bridge enable` aus U-Boot), Kernel unbeeindruckt. Der erste Versuch per SSH schien zu hängen — tatsächlich war nur das USB-WLAN weggebrochen (siehe Frage 7). Meldung „memory leak will occur if overlay removed“ ist harmlos (auch in Alteras Beispiel) |
| 2 PLL im I/O-Ring | **Eigene PLL im Kern ist erlaubt.** Gebaut: A und B gleicher `IO hash` (`A36E45D7…`), C mit eigener PLL `pll_c64` anderer `IO hash` (`849E8EB8…`); `HPS IO hash` bei allen gleich (`474D6C20…`). Auf dem Board lädt C trotzdem: ID `R25C`, PLL läuft mit richtiger Frequenz (LED 3: 29,67 s für 7 Zyklen = 4,24 s, Soll 4,26 s), A↔C 10× ohne Fehler. Erklärung (Hypothese, passt zu allen Beobachtungen): Im HPS-first-Betrieb gehören nur HPS-I/O und HPS-Speicher zum Flash-Teil; FPGA-I/O und PLLs kommen mit jedem `core.rbf` neu. Bindend ist der `HPS IO hash`. Nicht geprüft: abweichende Pin-Belegungen |
| 3 LW-Bridge nach dem Laden | **Ja.** Nach jedem Laden ID korrekt, SCRATCH schreib-/lesbar, `disk_m0` antwortet, UPTIME 0,05 s (Kern frisch gestartet) |
| 4 `/dev/mem`, DDR-Lage | `/dev/mem` geht (sysid `0xacd5cafe` gelesen). DDR des HPS: 1 GB ab `0x8000_0000`; `0x8000_0000–0x81FF_FFFF` reserviert (svc-Puffer), System RAM `0x8200_0000–0xBFFF_FFFF`. Für MiSTers 512-MB-Fenster bliebe Linux 512 MB |
| 5 U-Boot `fpga load` | **Ja.** Erster HPS-first-Boot 2026-10-15: Terasics SPL läuft unverändert, `1699840 bytes read in 89 ms … FPGA reconfiguration OK!`, danach `bridge enable` und Linux wie gewohnt; Lauflicht (Kern A) sichtbar |
| 6 `reboot` | **Ja im HPS-first-Betrieb** (2026-10-15: `sudo reboot` startet neu, U-Boot lädt den Kern wieder). Im FPGA-first-Betrieb (C64) hängt er nach dem Herunterfahren |
| 7 USB beim Laden | **Nur der WLAN-Stick.** Bei jedem Laden aus Linux bekommt der RT5370-Stick (`rt2x00usb`) während der Konfiguration USB-Zeitüberschreitungen (`error -110`) und verliert die Verbindung dauerhaft (Treiber neu laden, USB-Reset, Neu-Einstecken halfen nicht; erst Aus-/Einschalten). Tastatur und Gamepads: keine Ab-/Anmeldung über alle Wechsel. USB-Stick: 200 MB vor/nach dem Wechsel 11,4/11,2 MB/s, keine Fehler. → USB-Controller in Ordnung; fürs Netz Kabel-Ethernet nutzen (onboard `eth0` oder RTL8153-Adapter) Wiederbeleben scheitert: neu verbinden und Neustart von wpa_supplicant/NetworkManager helfen nicht; `modprobe -r rt2800usb` im Fehlerzustand **lässt den Kernel abstürzen** (Timer des entladenen Moduls, `__run_timers`). Nur Neustart hilft. **Lösung: vorbeugend Funk abschalten** (`p0_wlan.sh switch`: `nmcli radio wifi off` → Kern laden → `on`): 2× getestet, kein `error -110`, nach 3–4 s wieder online. Für Main_MiSTer: vor/nach jedem Kern-Laden Funk aus/an (z. B. `rfkill block/unblock wifi`) |

Vorprüfung 2026-10-15: Module `stratix10-soc`, `of-fpga-region`, `fpga-region`,
`fpga-bridge` vorhanden und geladen; `/sys/class/fpga_manager/fpga0`
(„Stratix10 SOC FPGA Manager“, Zustand `unknown`), `region0`, configfs-Overlays
da; keine `fpga_bridge`-Einträge (Brücken werden beim Laden nicht
abgeschaltet). Bootskript enthält `bridge enable` → `p0_bootscr.sh` passt.

Nebenbei erledigt: Root-Partition der SD-Karte (Terasic-Image: 3,4 GB, voll)
auf die ganze 29-GB-Karte vergrößert (`sfdisk -N 2`, Start 616449 behalten,
`resize2fs`). Sicherung der alten Tabelle: `~/mmcblk0-partitionen.txt`.
