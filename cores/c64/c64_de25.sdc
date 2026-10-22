# SPDX-License-Identifier: GPL-3.0-or-later
# c64_de25.sdc — Timing des C64-Cores (MiSTer hat dafür keine eigene .sdc).
#
# clk48 (OPL3, outclk0) und die C64-Takte (clk64, clk_sys, SDRAM-Takt) kommen
# aus derselben PLL, haben aber kein ganzzahliges Verhältnis (48,09 zu 31,53
# MHz). Quartus hält sie für synchron und findet zwischen ihnen Fenster von
# 0,35 ns. Gemeint ist der Übergang asynchron: Die OPL3 tauscht ihre Daten
# über einen dcfifo (opl3_fifo) und Synchronizer aus.
set_clock_groups -asynchronous \
	-group [get_clocks -nowarn {emu|pll|pll_c64_outclk0}] \
	-group [get_clocks -nowarn {emu|pll|pll_c64_outclk1 emu|pll|pll_c64_outclk2 emu|pll|pll_c64_outclk3}]
