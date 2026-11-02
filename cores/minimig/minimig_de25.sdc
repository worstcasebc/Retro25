# SPDX-License-Identifier: GPL-3.0-or-later
# minimig_de25.sdc — Timing des Amiga-Cores, übertragen aus MiSTers Minimig.sdc.
#
# Takte aus ip/pll_minimig (aus einem VCO, also synchron):
#   outclk0 clk_114 (113,5 MHz; SDRAM, DDR, CPU-Cache)
#   outclk1 clk_sys (28,375 MHz; Chipsatz, CPU)
# derive_pll_clocks entfällt: Die IOPLL-IP legt ihre Takte selbst an.
#
# Warum Multicycle? Chipsatz und CPU laufen mit clk_sys, der SDRAM-Controller
# (ram1) und der DDR-Controller (ram2) mit dem vierfachen Takt. Der Controller
# wertet Anforderungen erst zwei clk_114-Takte später aus (Erklärung in MiSTers
# Minimig.sdc), also hat der Pfad zwei statt eines clk_114-Takts Zeit.

set minimig_mc_from {
	emu|cpu_wrapper|cpu_inst*
	emu|amiga_clk|cck*
	emu|amiga_clk|c1*
	emu|amiga_clk|c3*
	emu|minimig|*
	emu|fastchip|akiko|*
	emu|chipdma_arb|*
}
foreach from $minimig_mc_from {
	set_multicycle_path -from [get_registers -nowarn $from] -to [get_registers -nowarn {emu|ram*}] -setup 2
	set_multicycle_path -from [get_registers -nowarn $from] -to [get_registers -nowarn {emu|ram*}] -hold 1
}

# Diese beiden Signale sind die Ausnahme: nur ein clk_114-Takt (wie MiSTer).
foreach from {emu|cpu_wrapper|cycles|hold emu|cpu_wrapper|inflight} {
	set_multicycle_path -from [get_registers -nowarn $from] -to [get_registers -nowarn {emu|ram*}] -setup 1
	set_multicycle_path -from [get_registers -nowarn $from] -to [get_registers -nowarn {emu|ram*}] -hold 0
}

# DMA-Schreibport auf ram2: Handschlag über Taktgrenzen. Die Daten stehen fest,
# bevor dmaCS über die 2-FF-Kette ankommt.
foreach reg {dma_ddr_addr_r dma_ddr_wr_r dma_ddr_l_r dma_ddr_u_r} {
	set_false_path -from [get_registers -nowarn "*chipdma_arb*${reg}*"] -to [get_registers -nowarn {*ddram_ctrl*}]
}
set_false_path -from [get_registers -nowarn {*chipdma_arb*dma_ddr_cs_r*}] -to [get_registers -nowarn {*ddram_ctrl*dmaCS_sync*}]
set_false_path -from [get_registers -nowarn {*ddram_ctrl*dmaACK_r*}]      -to [get_registers -nowarn {*chipdma_arb*ddr_in_ack_sync*}]

# Statische Einstellungen (ändern sich nur im OSD oder bei der Autokonfiguration)
set_false_path -from [get_registers -nowarn {emu|cpu_wrapper|z3ram_*}]
set_false_path -from [get_registers -nowarn {emu|cpu_wrapper|z2ram_*}]
set_false_path -from [get_registers -nowarn {emu|minimig|USERIO1|cpu_config*}]
set_false_path -from [get_registers -nowarn {emu|minimig|USERIO1|ide_config*}]
set_false_path -from [get_registers -nowarn {emu|minimig|USERIO1|bootrom}]
set_false_path -from [get_registers -nowarn {emu|minimig|CPU1|halt}]

# fx68k: MiSTers rtl/fx68k/fx68k.sdc
set_multicycle_path -start -setup -from [get_registers -nowarn {*fx68k*|Ir[*]}] -to [get_registers -nowarn {*fx68k*|microAddr[*]}] 2
set_multicycle_path -start -hold  -from [get_registers -nowarn {*fx68k*|Ir[*]}] -to [get_registers -nowarn {*fx68k*|microAddr[*]}] 1
set_multicycle_path -start -setup -from [get_registers -nowarn {*fx68k*|Ir[*]}] -to [get_registers -nowarn {*fx68k*|nanoAddr[*]}] 2
set_multicycle_path -start -hold  -from [get_registers -nowarn {*fx68k*|Ir[*]}] -to [get_registers -nowarn {*fx68k*|nanoAddr[*]}] 1
set_multicycle_path -start -setup -from [get_registers -nowarn {*|nanoLatch[*]}] -to [get_registers -nowarn {*|excUnit|alu|pswCcr[*]}] 2
set_multicycle_path -start -hold  -from [get_registers -nowarn {*|nanoLatch[*]}] -to [get_registers -nowarn {*|excUnit|alu|pswCcr[*]}] 1
set_multicycle_path -start -setup -from [get_registers -nowarn {*|excUnit|alu|oper[*]}] -to [get_registers -nowarn {*|excUnit|alu|pswCcr[*]}] 2
set_multicycle_path -start -hold  -from [get_registers -nowarn {*|excUnit|alu|oper[*]}] -to [get_registers -nowarn {*|excUnit|alu|pswCcr[*]}] 1
