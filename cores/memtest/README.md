# Memtest — SDRAM-Test (MiSTers MemTest auf dem DE25)

Prüft das 128-MB-SDRAM des DE25 (1,8 V, zwei Chip-Selects; getestet wird
wie bei MiSTer der erste Chip, 64 MB) mit MiSTers
[MemTest](https://github.com/MiSTer-devel/MemTest_MiSTer). Dient in P4 dazu,
den SDRAM-Takt für den C64 festzulegen.

- `vendor/` — Original, unverändert, nicht im Repository (`python tools/setup.py` bzw. `tools/fetch_memtest.py`)
- `pro/` — angepasste Kopien für Quartus Pro/Agilex 5; im Repository nur die Diffs `pro/*.patch` (`tools/apply_patches.py` erzeugt die Dateien)
- `ip/pll_memtest` — feste PLL: 64 MHz (wie clk64 des C64) und dieselbe
  Frequenz mit +90 Grad für `SDRAM_CLK`; `ip/pll_memtest_vid` — 27 MHz Video
- Bau: `python tools/make_core_qsf.py memtest`, dann `Q:\tools\build_core.bat memtest`

## Bedienung und Anzeige

Im Menü (F12) unter `_Retro25` als `Memtest`. Bildschirm von oben:

| Zeile | Farbe | Inhalt |
|---|---|---|
| 1 | gelb | Laufzeit in Minuten, Frequenz in MHz (fest 064) |
| 2 | türkis / grün | Speichergröße (2 = 64 MB) / bestandene Durchläufe (hex, je 32 MB) |
| 3 | rot | **Fehler** (hex, Anzahl falsch gelesener 16-bit-Werte) — bestanden bei 0 |

Enter setzt den Test zurück. Frequenz umstellen und Automatik (Tasten
hoch/runter, A) wirken hier nicht: Nur `sys` darf zur Laufzeit eine PLL
umstellen (zwei umgestellte HVIO-PLLs stören sich, siehe
`sys/de25/README.md`); jede Frequenz ist ein eigener Bau.

Aus der Ferne (Main nimmt Befehle über `/dev/MiSTer_cmd`):

```
echo "load_core /media/fat/_Retro25/Memtest.rbf" > /dev/MiSTer_cmd
echo screenshot > /dev/MiSTer_cmd     # PNG unter /media/fat/screenshots/MEMTEST/
```

## Anpassungen (pro/)

- **memtest.sv:** feste IOPLL statt der umstellbaren Cyclone-V-PLL samt
  `pll_cfg`; SDRAM-Takt vom zweiten PLL-Ausgang über das DDIO-Register
  `sys/de25/ip/sdram_clk_ddio` (`din = 2'b10`: Takt unverändert); feste
  Frequenzanzeige; Automatik aus; Falle 16754 (Register mit Startwert im
  always-Block).
- **sdram.v:** `inout reg` → Tri-State mit `dq_out`/`dq_oe`; `dq_out` ohne
  Clock-Enable (sonst passen Daten- und Freigaberegister nicht gemeinsam in
  die I/O-Zelle, Fitter-Fehler 14996/24403); `altddio_out` entfällt
  (`DRAM_CLK` unbenutzt); Falle 16754.
- **tester.v:** Falle 16754 — sonst startet der Test nie.

## Messungen (P4, 2026-10-17)

Alle mit I/O-Registern für Adresse, Befehle und Daten (`FAST_*_REGISTER` in
`sys/de25/sys_de25.tcl`, wie bei MiSTer) und SDRAM-Takt über das
DDIO-Register. Je 1,5–5 min, bei Fehlern ist der Zähler schon nach Sekunden
riesig (praktisch jeder Lesewert falsch).

| Frequenz | Phase SDRAM_CLK | Ergebnis |
|---|---|---|
| 64 MHz | 0° | fast alles falsch |
| 64 MHz | 45° | fehlerfrei |
| 64 MHz | **90°** | **fehlerfrei** (25 min, 707 Durchläufe) |
| 64 MHz | 135° | fehlerfrei |
| 64 MHz | 180° (invertiert, wie MiSTer) | fast alles falsch |
| 64 MHz | 270° | fast alles falsch |
| 100 MHz | 0° | fehlerfrei (5 min) |
| 100 MHz | 180° | fast alles falsch |

Ohne die I/O-Register fiel auch 100–140 MHz mit 180° durch (frühere Messung).

**Deutung:** MiSTers Controller liest die Daten nach einer festen Zahl von
Takten. Das passt bei MiSTer (Cyclone V, 3,3-V-SDRAM) zum invertierten Takt.
Beim DE25 kommen die Lesedaten später an (1,8-V-SDRAM und -Pins) — das
gültige Fenster liegt bei 64 MHz zwischen etwa 45° und 135°. Die passende
Phase hängt von der Frequenz ab, weil die Laufzeiten feste Zeiten sind
(64 MHz: 90° = 3,9 ns; 100 MHz: 0° geht, 180° nicht). Terasics SDRAM-Demo
erzeugt `DRAM_CLK` ebenfalls aus einem PLL-Ausgang mit Phase.

**Folge für den C64 (Entscheidung 2026-10-17):** zusätzlicher Ausgang der
C64-PLL, clk64 mit +90°, über `sdram_clk_ddio` (`din = 2'b10`) an
`SDRAM_CLK` statt des invertierten clk64. Sein Controller kann in einem
anderen Takt abtasten als der Memtest — die Phase wird mit dem C64 selbst
nachgeprüft.
