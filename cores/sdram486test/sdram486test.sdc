# SPDX-License-Identifier: GPL-3.0-or-later
# sdram486test.sdc — Timing des SDRAM-Tests für den z486 (wie memtest_de25.sdc).
#
# SDRAM-Takte (pll, 85 MHz und 85 MHz mit Phase) und Videotakt (vpll, 27 MHz)
# haben nichts miteinander zu tun: Die Zähler wandern ohne Synchronizer nur
# zur Anzeige. Die übrigen Gruppen (emu gegen sys) setzt sys_top_de25.sdc.
set_clock_groups -asynchronous \
	-group [get_clocks -nowarn {emu|pll|*outclk*}] \
	-group [get_clocks -nowarn {emu|vpll|*outclk*}]
