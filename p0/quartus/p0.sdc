# p0.sdc — Timing-Constraints für alle Revisionen des P0-Versuchs.
#
# Die Takte clk_100 (pll an CLOCK2_50) und in Revision C clk_c (pll_c64 an
# CLOCK0_50) legen die PLL-IPs mit ihren eigenen .sdc an. CLOCK0_50 ohne PLL
# (Revisionen A und B) steht in p0_clock0_50.sdc.

# Erste Stufe jedes Synchronizers (sync_2ff): asynchron per Definition.
set_false_path -to [get_registers {*|meta_q[*]}]
set_false_path -from [get_ports {KEY[*] SW[*]}]

# LEDs sind fürs Auge.
set_false_path -to [get_ports {LEDR[*]}]

# Revision C: Das LED-Muster entsteht in clk_c, die LEDs sind ohnehin
# ausgenommen; zwischen clk_c und clk_100 gibt es keine weiteren Wege.
