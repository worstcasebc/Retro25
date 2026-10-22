# p0_clock0_50.sdc — nur Revisionen A und B: CLOCK0_50 speist dort direkt
# den Herzschlag (in Revision C legt die PLL pll_c64 diesen Takt selbst an).
create_clock -name clock0_50 -period 20.000 [get_ports CLOCK0_50]
