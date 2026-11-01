# Einen MiSTer-Core nach Retro25 portieren

Stand: 2026-11-01, nach C64 (P4), z486 (P5) und NES (P6). Ziel: der nächste
Core in Stunden statt Tagen.

Analogie: `sys/` ist der fertige Steckplatz. Ein MiSTer-Core passt elektrisch
schon hinein (gleiche `emu`-Schnittstelle); was fehlt, ist die „Übersetzung“
vom Werkzeug des Herstellers (Quartus Standard, Cyclone V) auf unseres
(Quartus Pro, Agilex 5). Die meisten Stolpersteine sind immer dieselben —
deshalb gibt es dafür ein Werkzeug (`tools/port_core.py`).

## Ablauf in Kürze

| Schritt | Werkzeug | Ergebnis |
|---|---|---|
| 1. Lizenz prüfen | Lesen: `LICENSE`/`COPYING`, Dateiköpfe | darf Patch-Kontext veröffentlicht werden? |
| 2. Holen | `tools/fetch_<core>.py` (Vorlage: `fetch_nes.py`) | `cores/<core>/vendor/` |
| 3. Analysieren | `python tools/port_core.py <core> scan` | Liste der Baustellen |
| 4. Takt | `tools/make_iopll.py` | `cores/<core>/ip/pll_<core>.ip` |
| 5. Projekt | `core.tcl`, `<core>_de25.sdc`, `tools/make_core_qsf.py` | Quartus-Projekt |
| 6. Synthese-Schleife | `quartus_syn`, `port_core.py … fix13386/fiximplicit/report` | saubere Synthese |
| 7. Bau | `Q:\tools\build_core.bat <core>` | `.core.rbf`, Timing, Hash |
| 8. Board | `load_core`, MGL, Screenshot, Main-Log | läuft |

## 1. Lizenz

- GPL/Apache: Patches mit Kontext sind in Ordnung.
- **Ohne Weitergaberecht** (Beispiel FPGA64 im C64, `syntiac.com`: nur
  privat, auch geändert nicht weitergeben): keine `.patch` mit Originalzeilen,
  sondern `*.subst.json` (kurze Such-/Ersetzungsregeln, siehe
  `tools/apply_patches.py`). Bitstreams solcher Cores nie weitergeben.
- Lizenz in die `vendor/README.retro25.md` (das fetch-Skript schreibt sie).

## 2. Holen

Vorlage `tools/fetch_nes.py`: fester Commit, `sparse-checkout` nur für das
Benötigte (lange Pfade wie NES `Palette/` scheitern sonst unter Windows),
ohne Cyclone-V-PLL (`rtl/pll*`), `releases/`, `sys/`. Danach:

- `tools/setup.py`: Eintrag in `STEPS`
- `tools/apply_patches.py`: Paar `("cores/<core>/pro", "cores/<core>/vendor")`
- `.gitignore`: `cores/<core>/pro/**` mit Ausnahmen für `*.patch`
- `cores/<core>/build_id.v` (`` `define BUILD_DATE "jjmmtt" ``)

## 3. Analysieren

`python tools/port_core.py <core> scan` meldet:

- **Cyclone-V-Primitive** (`altsyncram`, `altddio_out`, `altera_pll` …)
- **13386-Kandidaten** (`wire`/`output` ohne Typ, in `always` beschrieben)
- **VHDL-`case` ohne `others`**
- **Paket-Import auf Dateiebene** (`import x::*;` gilt bei Pro nur in dieser Datei)
- **`.mif`-Pfade relativ zum MiSTer-Projekt** (`"rtl/x.mif"`)

Von Hand ansehen:

- **CONF_STR:** `SS…` (Savestates im DDR → Main braucht Patch 0011, ist
  drin), `UART` (MIDI), Dateieinträge `F…`/`S…` (Index für MGL-Tests).
- **PLL:** Stellt der Core sie um (`pll_cfg`, z. B. NTSC/PAL)? Bei uns
  verboten — nur `sys` stellt eine PLL um (zwei umstellbare HVIO-PLLs stören
  sich). Entscheidung: eine Norm fest (C64: PAL, NES: NTSC) oder zwei
  Revisionen.
- **SDRAM:** `SDRAM_CLK` per `altddio_out`/invertiertem Takt → PLL-Ausgang
  +90° über `sys/de25/ip/sdram_clk_ddio` (1,8-V-SDRAM des DE25: 0°…135°
  fehlerfrei, 180° nicht). `inout reg SDRAM_DQ` → Tri-State mit
  `dq_out`/`dq_oe`, Datenregister in jedem Takt laden, `(* preserve *)`.
- **DDRAM:** Bursts nie per Reset abbrechen (SMMU hängt sonst Linux auf);
  Bursts über 4-KB-Grenzen teilt `sys` (`avl_burst_4k`).
- **RAMs mit zwei Takten:** True-Dual-Port mit zwei Takten kann Agilex-5-M20K
  nicht (22556). Beide Ports an denselben Takt, wenn die Takte aus einer PLL
  stammen und flankengleich sind (NES-EEPROM).

## 4. Takt

Die Agilex-IOPLL ist ganzzahlig: VCO = 50 MHz · M / N, Ausgang = VCO / C.
MiSTers fraktionale Frequenzen trifft man mit passendem M/N/C oft exakt.
Suche (Beispiel NES, 85,909091 MHz = 945/11):

```python
f = 945/11
for N in range(1, 11):
    for M in range(4, 320):
        vco = 50*M/N
        if 600 <= vco <= 3000:
            for C in range(1, 128):
                if abs(vco/C - f)/f < 30e-6: print(N, M, C, vco, vco/C)
```

Dann: `python tools/make_iopll.py cores/<core>/ip/pll_<core>.ip M N C0 C1 … Cx@90`
(letzter Ausgang mit `@90` für `SDRAM_CLK`). Modulname nie `pll` — kollidiert
mit der PLL im HPS-System.

## 5. Projekt

- `core.tcl`: Dateiliste aus `vendor/files.qip` samt Unter-`.qip`
  ausgeschrieben (Skript-Schnipsel in der NES-Historie), angepasste Dateien
  aus `{CORE}/pro/`. **Pakete zuerst** (Quartus Pro übersetzt in
  Listenreihenfolge). `.v` mit `import` als `SYSTEMVERILOG_FILE`.
  `SEARCH_PATH {CORE}` für `build_id.v`.
- `<core>_de25.sdc`: MiSTers `.sdc` mit unseren Taktnamen
  (`emu|pll|pll_<core>_outclkN`); `derive_pll_clocks` ist überflüssig, die
  IOPLL-IP legt ihre Takte selbst an.
- `python tools/make_core_qsf.py <core>`

## 6. Synthese-Schleife

```
python tools/port_core.py <core> fix13386 --apply
Set-Location Q:\cores\<core>\quartus; quartus_syn <core> -c <core>
python tools/port_core.py <core> fiximplicit --apply   # liest den Bericht
quartus_syn …   (wiederholen, bis fehlerfrei)
python tools/port_core.py <core> report
```

`--apply` schreibt die `pro/`-Kopie, deren `.patch` und stellt `core.tcl`
um. Handänderungen an `pro/`-Dateien danach mit
`python tools/apply_patches.py --make <datei>` in den Patch übernehmen.

Quartus Pro meldet je Datei oft nur den ersten Fehler und überspringt dann
ganze Module — deshalb lieber im ganzen Quelltext suchen als Meldung für
Meldung abarbeiten.

### Fehler und Warnungen, die bei uns Folgen hatten

| Code | Bedeutung | Abhilfe |
|---|---|---|
| 13386 | `wire`/`output` in `always` beschrieben | `logic` (`fix13386`) |
| 13406 | Bezeichner unbekannt — oft Paket-Import nur in einer Datei | `import` je Datei, Paket zuerst |
| 16746/16749 → **16788** | Benutzung vor `wire x = ausdruck;`: implizites Netz, Zuweisung verworfen, **Netz ohne Treiber** (NES: PPU, CPU-Decoder, Reset) | `fiximplicit` |
| **16754** | Register mit Startwert in `always`: Pro setzt es **jeden Takt** zurück | Startwert weg (bei 0) oder Register auf Modulebene |
| 13034/13035/13028 | Tri-State falsch aufgelöst (z486: `gamma_bus = 'z`) | Tri-State im Core vermeiden |
| 13630 / 17577 | VHDL `case` ohne `others`; `'range` auf Integer-Subtyp | `when others`; `array (typ)` |
| 13780 | direkte Instanz ohne `entity` | `entity work.x` |
| 272006 | `altsyncram` BIDIR mit `clock1`, `ramstyle "M10K"` | inferiertes RAM (NES `rtl/dpram.vhd`) |
| 22556 | TDP-RAM mit zwei Takten | ein Takt für beide Ports |
| 276009 | RAM nicht inferiert (Lese-/Schreibverhalten) | `(* ramstyle = "no_rw_check" *)` |
| 287078 | `altddio_out` | `sdram_clk_ddio` |
| 20059 | `.mif` nicht gefunden | Pfad `../vendor/rtl/x.mif` (relativ zu `quartus/`) |
| Absturz | `ram_init_file = " "` | Attribut nur mit echter Datei |

Ziel nach der Schleife: im Core-Code 0 × 16754, 16788 nur für bewusst
teilweise belegte Busse (NES: `SS_*_BACK`), 0 × 1303x. Mehr in
`sys/de25/README.md` (Abschnitt Quartus-Pro-Fallen).

## 7. Bau

`Q:\tools\build_core.bat <core>` (oder `quartus_sh --flow compile` +
`quartus_pfg`, siehe Batch-Datei). Prüfen:

- Timing: Setup/Hold/Recovery/Removal „Pass“ (`<core>.sta.rpt`)
- `HPS IO hash is 474D6C20…` in `<core>_pfg.log` — sonst lädt Linux den
  Core nicht
- Belegung (`<core>.fit.summary`): Platz bis ~46,8k ALMs

## 8. Board

```
scp cores/<core>/quartus/output_files/<core>.core.rbf terasic@192.168.178.125:/media/fat/_Retro25/<Name>.rbf
echo "load_core /media/fat/_Retro25/<Name>.rbf" > /dev/MiSTer_cmd
```

Ein Main-Neustart lädt das FPGA nicht neu — immer `load_core`. Vorher
nachsehen, was läuft (Screenshot), bei Windows 95 erst herunterfahren lassen.

Test ohne Nutzer: MGL mit Spiel (`<file delay="1" type="f" index="N"
path="/media/fat/games/<Core>/x"/>`, `N` = Ziffer des `F`-Eintrags, ohne
Ziffer 0), dann `echo screenshot > /dev/MiSTer_cmd`, Bild aus
`/media/fat/screenshots/<Core>/`. Im Journal (`journalctl -u retro25-main`)
nach `code=killed, status=7/BUS` sehen: SIGBUS heißt fast immer, dass Main
direkt in die `/dev/mem`-Abbildung des DDR schreibt — auf dem DE25
Device-Speicher → über `shmem_put`/`shmem_get` umbauen (Patches 0005, 0006,
0009, 0011).

## Erfahrungswerte

| Core | ALMs | M20K | Takt | Besonderheiten |
|---|---|---|---|---|
| C64 | 35 589 (76 %) | 222 | PAL fest | FPGA64-Lizenz, 1541 über DDRAM |
| z486 | 43 159 (92 %) | 282 | 85 MHz | eigenes `make_pro.py`, x87, SVGA |
| NES | 39 879 (85 %) | 90 | NTSC fest | ~200 Stellen Quartus-Pro-Fallen, Main-Patch 0011 |
