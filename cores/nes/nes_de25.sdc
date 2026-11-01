# SPDX-License-Identifier: GPL-3.0-or-later
# nes_de25.sdc — Timing des NES-Cores, übertragen aus MiSTers NES.sdc.
#
# Takte aus ip/pll_nes (alle aus einem VCO, also synchron):
#   outclk0 clk85 (SDRAM-Controller), outclk1 CLK_VIDEO (clk85/2),
#   outclk2 clk (clk85/4, Konsole), outclk3 clk85 +90 Grad (nur SDRAM_CLK)
#
# MiSTer: Der SDRAM-Controller läuft mit clk85, die Konsole liest seine
# Ausgaben aber mit clk (21,5 MHz) und gibt ihre Anforderungen in clk aus.
# Der Controller wertet sie erst nach zwei clk85-Takten aus bzw. hält die
# Daten lange genug -> Multicycle 2 (Setup) / 1 (Hold), wie im Original.
# Ohne diese Regeln verlangt Quartus den Übergang in einem clk85-Takt.
set nes_clk  [get_clocks -nowarn {emu|pll|pll_nes_outclk2}]

set_multicycle_path -from [get_registers {emu|sdram|*}] -to $nes_clk -start -setup 2
set_multicycle_path -from [get_registers {emu|sdram|*}] -to $nes_clk -start -hold 1
set_multicycle_path -from $nes_clk -to [get_registers {emu|sdram|*}] -setup 2
set_multicycle_path -from $nes_clk -to [get_registers {emu|sdram|*}] -hold 1

# Statisch nach dem Laden eines Spiels (wie MiSTer)
set_false_path -from [get_registers -nowarn {emu|mapper_flags*}]
set_false_path -from [get_registers -nowarn {emu|downloading*}]
