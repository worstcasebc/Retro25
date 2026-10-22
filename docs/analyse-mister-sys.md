# Analyse: MiSTer `sys/` → Agilex 5 (DE25-Nano)

Quelle: Template_MiSTer, Commit 9c8eadb (2026-10-10); HPS-Seite aus Main_MiSTer
(`fpga_io.cpp`, `spi.cpp`, `fpga_base_addr_ac5.h`). Stand 2026-10-14.
**[prüfen]** = Agilex-5-/DE25-Fakt, noch nicht gegen Dokumentation bestätigt.

## Was ist Cyclone-V-spezifisch?

| Stelle | Cyclone-V-Teil | Agilex-5-Ersatz | Aufwand |
|---|---|---|---|
| `sys_top.v` | `cyclonev_hps_interface_mpu_general_purpose` (gp_in/gp_out) | eigenes Register `hps_gp_bridge` an der LW-Bridge | mittel |
| `sys_top.v` | HPS-Peripherie ins FPGA geführt: UART (MIDI), I2C (HDMI), SPI-Master (ALSA), IRQs | HDMI-I2C: über HPS geroutet oder Soft-I2C [prüfen]; UART/ALSA zunächst weglassen; IRQ über F2H | gering–mittel |
| `sys_top.v` | 2× `cyclonev_clkselect`, 2× `altddio_out` (Pixeltakt invertiert ausgeben) | Clock-Control-IP bzw. fester Takt; GPIO-IP mit DDR-Ausgang | gering |
| `sysmem.sv` | `fpga2sdram` mit 3 Avalon-Ports (vbuf 128 bit für ascal, ram1 64 bit = DDRAM des Cores, ram2 64 bit ALSA/Palette), `clocks_resets` (clk_100m, h2f_rst_n) | ein F2SDRAM-AXI4-Port → Arbitrierung/Taktübergang im Platform Designer, Adress-Offset, reserved-memory im Device-Tree | **hoch** |
| PLLs | `pll_hdmi` (fraktional, 148,5 MHz, rekonfigurierbar), `pll_audio` (24,576 MHz), `pll_cfg` (altera_pll_reconfig), `pll_hdmi_adj.vhd` (Low-Latency) | IOPLL + IOPLL Reconfig — andere Registerkarte, vermutlich nur ganzzahlig [prüfen]; Main_MiSTer rechnet die PLL-Werte selbst (Kommando 0x20) → dort neue Mathematik; Low-Latency neu lösen | **hoch** |
| Audio-PLL | `altera_pll` | IOPLL 50 MHz × 29 / 59 = 24,57627 MHz (+11 ppm) [VCO-Bereich prüfen] | gering |
| `sd_card.sv` | `altsyncram` | inferiertes RAM | gering |
| Build | `sys.tcl` (Pins, HPS_LOCATION), `sys_top.sdc` (`derive_pll_clocks`), `sys.qip` wählt `pll_q<Version>.qip`, `build_id.tcl` (jtag.cdf) | neue `sys_de25.tcl`, Pro-taugliche qsf/sdc, `.ip`-Dateien, `pll_q26.qip` | mittel |
| Cores | jeder Core hat eigenes `rtl/pll` (altera_pll) | je Core IOPLL neu erzeugen | mittel je Core |

Generisch und nur auf Übersetzbarkeit zu prüfen: `ascal.vhd`, `osd.v`,
`hps_io.sv`, Audio-Kette, Video-Helfer, `f2sdram_safe_terminator.sv`.

Für den ersten Bring-up weglassen: analoges VGA/YC, SPDIF, Sigma-Delta,
MiSTer-I/O-Board (MCP23009), USER_IO, SD-SPI, ADC, SDRAM2, ALSA, UART.
Start mit `MISTER_DEBUG_NOHDMI` (Direktvideo ohne Scaler und ohne HDMI-PLL).
**Der Menü-Core braucht ascal + Framebuffer im DDR** — er geht erst, wenn
F2SDRAM steht.

## emu-Schnittstelle (`emu_ports.vh`) — unverändert lassen

- Takt/Bus: `CLK_50M`, `RESET`, `HPS_BUS[45:0]`
- Video: `CLK_VIDEO`, `CE_PIXEL`, `VIDEO_ARX/ARY[12:0]`, `VGA_R/G/B[7:0]`,
  `VGA_HS/VS/DE/F1`, `VGA_SL[1:0]`, `VGA_SCALER`, `VGA_DISABLE`,
  `HDMI_WIDTH/HEIGHT[11:0]`, `HDMI_FREEZE/BLACKOUT/BOB_DEINT`, `LFB_*`
- Framebuffer (`MISTER_FB`): `FB_EN/FORMAT/WIDTH/HEIGHT/BASE/STRIDE/VBL/LL/FORCE_BLANK`,
  mit `MISTER_FB_PALETTE` zusätzlich `FB_PAL_*`
- LEDs/Tasten: `LED_USER`, `LED_POWER[1:0]`, `LED_DISK[1:0]`, `BUTTONS[1:0]`
- Audio: `CLK_AUDIO`, `AUDIO_L/R[15:0]`, `AUDIO_S`, `AUDIO_MIX[1:0]`
- DDR: `DDRAM_CLK/BUSY/BURSTCNT[7:0]/ADDR[28:0]` (64-bit-Wortadresse)`/DOUT[63:0]/DOUT_READY/RD/DIN[63:0]/BE[7:0]/WE`
- SDRAM: `SDRAM_CLK/CKE/A[12:0]/BA[1:0]/DQ[15:0]/DQML/DQMH/nCS/nCAS/nRAS/nWE`
- Sonstiges: `ADC_BUS`, `SD_*`, `UART_*`, `USER_IN/OUT[6:0]`, `OSD_STATUS`

## Das hps_io-Protokoll auf Busebene

Auf dem Cyclone V sind gp_out (0xFF706010) und gp_in (0xFF706014) Register im
FPGA-Manager. Analogie: zwei Briefkästen — einer, in den Linux Briefe
einwirft, einer, aus dem es Antworten holt; das Fähnchen (Strobe) zeigt an,
dass ein neuer Brief drin ist.

**gp_out (HPS → FPGA):** [15:0] Daten, [17] Strobe, [18] ss0 = Datei-I/O,
[19] ss1 = OSD, [20] ss2 = User-I/O, [29] Disk-LED, [31:30] Reset
(01 = Core im Reset, 00 → 10 gibt frei; [31]=0 lässt gp_in die Kennung liefern).

**gp_in (FPGA → HPS):** [15:0] Daten, [16] WIDE, [17] ACK, [19:18] io_ver=1,
[20] ~HDMI_INT, [28] io_dig, [29] OSD-Taste, [30] User-Taste, [31] = 1 wenn
das FPGA nicht konfiguriert ist. Kennung bei gp_out[31]=0: `{24'h5CA623, 8'hA4}`.

**Chip-Selects:** io_fpga = ss0 & ~ss1 (Dateitransfer 0x53–0x56),
io_uio = ss2 & ~ss1 (hps_io + Konfig-Decoder in sys_top), OSD = ss1.
Abfallendes Select beendet ein Kommando.

**FPGA-Seite (clk_sys):** gp_out über 2 FF synchronisiert; jede steigende
Flanke von Bit 17 erzeugt einen io_strobe; io_ack folgt 2 Takte später, friert
aber ein, solange io_wait (ioctl_wait) oder vs_wait gesetzt ist (Flusskontrolle).
Daten werden nicht eigens synchronisiert — HPS legt sie vor/mit dem Strobe an.

**HPS-Seite:** Handshake-Modus (`fpga_spi`: Daten, +Strobe, auf ACK=1 warten,
Strobe weg, auf ACK=0 warten, gp_in lesen) und schneller Blockmodus für
Sektoren (Wort, Wort|Strobe, lesen — **ohne** ACK-Abfrage, 16-fach entrollt).

**Nachbildung auf dem Agilex 5 (`hps_gp_bridge`, Vorschlag):**
- `0x00` GPO (R/W): Schreibzugriff per waitrequest anhalten, bis die
  clk_sys-Domäne den Wert übernommen hat (Toggle-Handshake) — so geht bei
  schnellen, gepufferten A76-Schreibzugriffen keine Strobe-Flanke verloren.
  Nicht auf io_ack warten (vs_wait kann bis 16 ms dauern); Timeout einbauen.
- `0x04` GPI (R): Momentaufnahme mit gleichem Handshake; Bit 31 = 1, wenn
  clk_sys nicht läuft.
- optional `0x08` DATA_STB / `0x0C` DOUT für einen schnelleren Pfad, `0x10` ID.
- Handshake-Logik in sys_top und `hps_io.sv` bleiben unverändert.

## DDR-Adressen (Cyclone V)

FPGA sieht 0x20000000–0x3FFFFFFF (ascal ab 0x20000000, Cores meist ab
0x30000000); Linux hat 512 MB. Agilex 5: DDR physisch ab 0x8000_0000 [prüfen]
→ Fenster per reserved-memory (`no-map`) reservieren, im sysmem-Ersatz
Offset addieren; Bridges vor dem Neuladen abschalten.
