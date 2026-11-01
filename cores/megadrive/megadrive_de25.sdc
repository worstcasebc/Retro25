# SPDX-License-Identifier: GPL-3.0-or-later
# megadrive_de25.sdc — Timing des MegaDrive-Cores, übertragen aus MiSTers
# MegaDrive.sdc.
#
# Takte aus ip/pll_md (alle aus einem VCO, also synchron):
#   outclk0 clk_53m (clk_sys), outclk1 clk_107m (clk_md/clk_ram),
#   outclk2 clk_53m_v (CLK_VIDEO), outclk3 clk_107m mit Phase (nur SDRAM_CLK)
# derive_pll_clocks entfällt: die IOPLL-IP legt ihre Takte selbst an.

# psg_iir lädt seine Register nur mit ce_flt (7-MHz-Freigabe auf clk_sys),
# wie im Original
set_multicycle_path -from {*|psg_iir|*} -to {*|psg_iir|*intreg*} -setup 2
set_multicycle_path -from {*|psg_iir|*} -to {*|psg_iir|*intreg*} -hold 1
