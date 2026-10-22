# SPDX-License-Identifier: GPL-3.0-or-later
# memtest_de25.sdc — Timing des Memtest-Cores (statt vendor/memtest.sdc).
#
# SDRAM-Takte (pll, 64 MHz und +90 Grad) und Videotakt (vpll, 27 MHz) haben nichts
# miteinander zu tun: Die Zähler wandern ohne Synchronizer nur zur Anzeige.
# Wie im Original (dort -exclusive) als asynchron erklären. Die übrigen
# Gruppen (emu gegen sys) setzt sys/de25/sys_top_de25.sdc.
set_clock_groups -asynchronous \
	-group [get_clocks -nowarn {emu|pll|*outclk*}] \
	-group [get_clocks -nowarn {emu|vpll|*outclk*}]
