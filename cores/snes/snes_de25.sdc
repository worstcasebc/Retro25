# SPDX-License-Identifier: GPL-3.0-or-later
# snes_de25.sdc — Timing des SNES-Cores, übertragen aus MiSTers SNES.sdc.
#
# Takte aus ip/pll_snes (alle aus einem VCO, also synchron):
#   outclk0 clk_mem (85,9 MHz, SDRAM-Controller), outclk1 CLK_VIDEO (clk_mem/2),
#   outclk2 clk_sys (clk_mem/4, Konsole), outclk3 clk_mem +90 Grad (SDRAM_CLK)
# derive_pll_clocks entfällt: die IOPLL-IP legt ihre Takte selbst an.
#
# Entfallen: MiSTers GSU_CACHE_CLK und CX4_MEM_CLK (invertierte Takte an den
# altsyncram-Pins, als asynchron erklärt). rtl/bram.vhd (dpram_difclk)
# arbeitet mit "not CLK" als fallender Flanke von clk_sys; Quartus prüft die
# Pfade dazwischen als halben Takt (23 ns) — enger als MiSTer, aber korrekt.

# Konsole (clk_sys) -> SDRAM-Controller (clk_mem) und zurück: MiSTer erlaubt
# 20 bzw. 23 ns statt eines clk_mem-Takts (11,6 ns), weil der Controller die
# Anforderungen erst einige Takte später übernimmt bzw. die Daten hält.
set_max_delay 20 -from [get_registers -nowarn { emu|hps_io|* \
                                                emu|main|* \
                                                emu|bsram|* \
                                                emu|rom_mask[*] \
                                                emu|rom_type[*] }] \
                 -to   [get_registers -nowarn { emu|sdram|addr[*][*] \
                                                emu|sdram|din[*][*]* \
                                                emu|sdram|rfs* \
                                                emu|sdram|write[*] \
                                                emu|sdram|read[*] \
                                                emu|sdram|word[*] \
                                                emu|sdram|old_* \
                                                emu|sdram|is_sni[*] \
                                                emu|sdram|st_num[*]* \
                                                emu|sdram|state[1]* \
                                                emu|sdram|SDRAM_nCAS \
                                                emu|sdram|SDRAM_nRAS \
                                                emu|sdram|SDRAM_nWE \
                                                emu|sdram|dq_out[*] \
                                                emu|sdram|dq_oe \
                                                emu|sdram|SDRAM_A[*] \
                                                emu|sdram|SDRAM_BA[*] }]

set_max_delay 23 -from [get_registers -nowarn { emu|sdram|* }] \
                 -to   [get_registers -nowarn { emu|main|* \
                                                emu|bsram|* \
                                                emu|vram*|* }]

set_false_path -from [get_registers -nowarn { emu|sdram_download_* }] -to [get_registers -nowarn { emu|main|* }]
set_false_path -from [get_registers -nowarn { emu|en216p }]
