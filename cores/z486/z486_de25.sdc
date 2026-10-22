# SPDX-License-Identifier: GPL-3.0-or-later
# z486_de25.sdc — Timing des z486 im Retro25-Rahmen (P5/Z4).
#
# Ein Core-Takt: clk_sys 85 MHz aus ip/pll_z486 (dient auch als CLK_VIDEO und
# DDRAM_CLK); der zweite PLL-Ausgang (85 MHz/90°) geht nur an das DDIO-Register
# von SDRAM_CLK. Gruppen emu gegen sys setzt sys_top_de25.sdc.
derive_pll_clocks
derive_clock_uncertainty

# Ab hier wie upstream vendor/z486_mister.sdc:
# Reset-/Freigabepfade sind absichtlich asynchron.
set_false_path -from [get_registers -nowarn {*cpu_reset_n*}]
set_false_path -from [get_registers -nowarn {*reset_sync_r*}]
set_false_path -from [get_registers -nowarn {*boot_done*}]

# seg_linear -> early_rd_present ist ein Scheinpfad (komplexer gegen
# nicht-komplexer Zweig schließen sich aus; Begründung upstream).
set_false_path -through [get_nets -nowarn {*seg_unit|Add0*}] \
               -through [get_nets -nowarn {*early_rd_present*}]
