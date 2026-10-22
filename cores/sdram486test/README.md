# sdram486test — SDRAM-Test für den z486-Controller (P5 Z3)

Prüft upstreams SDRAM-Controller des z486 (`cores/z486/pro/src/memory/sdram.v`)
auf dem Onboard-SDRAM des DE25-Nano, bevor der ganze z486 darauf läuft.
Rahmen und Anzeige stammen aus MiSTers MemTest (`cores/memtest`).

## Dateien

| Datei | Zweck |
|---|---|
| `rtl/tester486.v` | Prüfablauf + upstream-Controller (85 MHz, `HAS_DQM=1`, 128 MB) |
| `rtl/sdram486test.sv` | `emu`: Takte, Reset, Anzeige (aus MemTest abgeleitet, GPL-2.0-or-later) |
| `core.tcl`, `sdram486test.sdc`, `build_id.v` | Projekt (`tools/make_core_qsf.py sdram486test`) |
| `make_variants.py` | je Phase eine PLL (`ip/pNNN/pll_486.ip`, per `ip-deploy`) und eine Revision `sdram486test_pNNN` |
| `../../tb/tb_tester486.v` | Testbench (Questa) mit zwei Chip-Modellen `tb/sdram_chip_model.v` |

Bauen: `python cores/sdram486test/make_variants.py`, dann
`Q:\tools\build_core.bat sdram486test sdram486test_p090`.

## Was geprüft wird

Ein Durchlauf über die ganzen 128 MB (beide Chips; `SDRAM_nCS2 = ~SDRAM_nCS`
in `sys_top_de25.v`, wie MiSTers 128-MB-Modul):

1. jedes Dword voll schreiben — Muster `{~i[24:16], i[6:0], i[15:0]} ^ seed`
   (je Adresse eindeutig, beide Hälften verschieden, `seed` wechselt je
   Durchlauf)
2. je Dword ein Byte über DQM überschreiben (Byte-Spur wechselt)
3. alles lesen und vergleichen: gerade Durchläufe als Line Reads (4 Dwords
   mit Wrap ab wechselndem Start-Dword, wie der Cache der CPU), ungerade als
   lineare Bursts zu 8 Dwords

Fehler zählen: falsches Dword, falsche Anzahl Antworten, Zeitüberschreitung.
Ein Durchlauf dauert bei 85 MHz etwa 7 s.

Anzeige: oben Laufzeit (Minuten) und Phase von `SDRAM_CLK` in Grad, Mitte
`3` (= 128 MB) und Durchläufe (hex), unten Fehler (hex). OSD: „Reset Test“.

## Testbench

`python tb/run_sim.py tb_tester486` — echter Controller, zwei Chip-Modelle
(prüfen tRCD, tRP, tRC, tRAS, tRFC, Befehlsfolge, Bank-Zustand). Ergebnis:
zwei Durchläufe ohne Fehler, beide Chips gleich oft benutzt; Gegenprobe mit
gekipptem Datenbit in Chip 1 zählt genau dessen Dwords als Fehler.

## Ergebnisse am Board (85 MHz, CL2, tRCD/tRP 2, tRC 6)

| Phase SDRAM_CLK | Ergebnis (Fehler hex) |
|---|---|
| 0° | fehlerfrei (2,5 min, 21 Durchläufe) |
| 45° | fehlerfrei (2,5 min, 21 Durchläufe) |
| 90° | fehlerfrei (10 min, 88 Durchläufe) |
| 135° | fehlerfrei (2,5 min, 21 Durchläufe) |
| 180° | Rand: ~0x39E00 Fehler in 21 Durchläufen (vereinzelt) |
| 225° | 0x2A000000 = jedes Dword in jedem Durchlauf falsch |
| 270° | 0x2A000000 = jedes Dword falsch |
| 315° | 0x29FFFFC0 = fast jedes Dword falsch |

Fenster also etwa 0°…135° (Mitte ~67°). Gewählt: **90°** — liegt gut
im Fenster (≥ 45° = 1,5 ns Abstand zu beiden Kanten) und ist dieselbe Phase
wie beim C64 (`sdram_clk_ddio`), also eine Einstellung für alle Cores.
Hinweis: Bei 2,5 min je Phase ist „fehlerfrei“ nur grob; 90° lief zusätzlich
10 min.
