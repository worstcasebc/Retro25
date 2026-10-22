# SPDX-License-Identifier: GPL-3.0-or-later
# sys_top_de25.sdc — Timing-Vorgaben für sys_top_de25 (alle Cores).
#
# Angelehnt an MiSTers sys_top.sdc: Alle Taktdomänen werden gegeneinander
# als asynchron erklärt, weil zwischen ihnen nur Synchronizer, Handshakes oder
# Zwei-Takt-Speicher liegen (so auch hps_gp_bridge). Die Takte der PLLs legen
# die IOPLL-IPs mit ihren eigenen .sdc an; die Namen unten greifen per Muster
# auf die Instanzen (hps_pll, pll_audio, emu|…).

# CLOCK1_50 (pll_hdmi) und CLOCK2_50 (hps_pll, meist auch die PLL des Cores)
# bekommen ihren Takt von den IOPLL-IPs; nur CLOCK0_50 braucht einen eigenen.
# Diese Datei muss NACH allen IPs gelesen werden (Reihenfolge in der .qsf),
# sonst gibt es deren Takte hier noch nicht — sys_de25.tcl führt sie zuletzt auf.
create_clock -name CLOCK0_50 -period 20.000 [get_ports CLOCK0_50]

derive_clock_uncertainty

# Gruppiert wird nach PLL-Ausgängen. Die Referenztakte (CLOCK1/2_50) bilden
# eine eigene Gruppe: Quartus benennt den Takt an CLOCK2_50 nach der ersten PLL,
# die ihn nutzt (oft die des Cores), Logik daran (Tasten, reset_req) gehört aber
# zu sys_top, nicht zum Core.
set_clock_groups -asynchronous \
	-group [get_clocks -nowarn {hps_pll|*outclk*}] \
	-group [get_clocks -nowarn {pll_audio|*outclk*}] \
	-group [get_clocks -nowarn {pll_hdmi|*outclk*}] \
	-group [get_clocks -nowarn {emu|*outclk*}] \
	-group [get_clocks -nowarn {*refclk *|ref_clk0}] \
	-group [get_clocks -nowarn {CLOCK0_50}]

# Erste Stufe aller Synchronizer (Namenskonvention: "meta" im Registernamen,
# z. B. sync_2ff|meta_q, hps_gp_bridge|*_meta_q): asynchron per Definition.
set_false_path -to [get_registers -nowarn {*meta_q* *|*meta_q*}]

# Asynchrone Eingänge (gehen durch Synchronizer bzw. Entpreller)
set_false_path -from [get_ports {KEY[*] SW[*] HDMI_TX_INT HDMI_I2C_SDA}]

# Fürs Auge bzw. langsam: LEDs, I2C (100 kHz), I2S zum HDMI-Sender
set_false_path -to [get_ports {LEDR[*] HDMI_I2C_SCL HDMI_I2C_SDA}]
set_false_path -to [get_ports {HDMI_MCLK HDMI_SCLK HDMI_LRCLK HDMI_I2S}]

# HDMI-Video: wie bei MiSTer ohne Ausgangs-Constraints. Die Daten wechseln mit
# der fallenden Flanke von clk_vid, der Sender übernimmt mit der steigenden
# (halbe Periode Abstand, 6,7 ns bei 74,25 MHz); Ausgangsregister liegen im
# I/O-Block (FAST_OUTPUT_REGISTER in sys_de25.tcl).
set_false_path -to [get_ports {HDMI_TX_D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS HDMI_TX_CLK}]

# Einstellungen aus Main_MiSTer (selten geändert, wie im Original)
set_false_path -to   [get_registers -nowarn {cfg[*]}]
set_false_path -from [get_registers -nowarn {cfg[*]}]
set_false_path -from [get_registers -nowarn {VSET[*]}]
set_false_path -to   [get_registers -nowarn {wcalc[*] hcalc[*]}]
set_false_path -to   [get_registers -nowarn {hdmi_width[*] hdmi_height[*]}]
set_false_path -to   [get_registers -nowarn {deb_* btn_en btn_up}]
set_false_path -to   [get_registers -nowarn {WIDTH[*] HFP[*] HS[*] HBP[*] HEIGHT[*] VFP[*] VS[*] VBP[*]}]
set_false_path -from [get_registers -nowarn {WIDTH[*] HFP[*] HS[*] HBP[*] HEIGHT[*] VFP[*] VS[*] VBP[*]}]
set_false_path -to   [get_registers -nowarn {vol_att[*] scaler_flt[*] led_overtake[*] led_state[*]}]
set_false_path -from [get_registers -nowarn {vol_att[*] scaler_flt[*] led_overtake[*] led_state[*]}]
set_false_path -from [get_registers -nowarn {aflt_* acx* acy* areset* arc*}]
set_false_path -from [get_registers -nowarn {arx* ary*}]
set_false_path -from [get_registers -nowarn {vs_line*}]

# OSD (wie im Original)
set_multicycle_path -to [get_registers -nowarn {*_osd|osd_vcnt*}] -setup 2
set_multicycle_path -to [get_registers -nowarn {*_osd|osd_vcnt*}] -hold 1
set_false_path -to   [get_registers -nowarn {*_osd|v_cnt* *_osd|v_osd_start* *_osd|v_info_start* *_osd|h_osd_start* *_osd|half}]
set_false_path -from [get_registers -nowarn {*_osd|v_osd_start* *_osd|v_info_start* *_osd|h_osd_start* *_osd|rot* *_osd|dsp_width*}]
