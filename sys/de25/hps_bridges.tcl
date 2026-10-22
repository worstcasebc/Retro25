# SPDX-License-Identifier: GPL-3.0-or-later
# hps_bridges.tcl — führt zwei Stücke des LW-Bridge-Busses aus Terasics GHRD
# heraus (wie im C64-DE25-Projekt von Hand in Platform Designer, dort
# INSTALL.md C4).
#
# Aufruf: von tools/fetch_hps.py, wenn die Brücken in der Quelle fehlen (oder
# von Hand, im Ordner mit qsys_top.qsys):
#     qsys-script --system-file=qsys_top.qsys --script=<pfad>/hps_bridges.tcl
#                 --quartus-project=<Wegwerf-Projekt>
# Mehrfach ausführbar: vorhandene Brücken werden zuerst entfernt.
#
# Analogie: Steckdosen in der Hauswand — der Bus bleibt im System, die
# Geräte (Register im Top-Level) werden von außen eingesteckt.
#
#   Brücke       Adressbreite  Basis an pb_cpu_0.m0  Export  Linux-Adresse
#   c64_bridge    4 bit        0x0001_0100           c64_m0  0x2001_0100
#   disk_bridge  14 bit        0x0001_4000           disk_m0 0x2001_4000
#
# Retro25 nutzt c64_m0 für die gp-Register (hps_gp_bridge) und disk_m0 für
# DDR-Sperre, PLL-, I2C- und Paletten-Register (sys/de25/sys_top_de25.v).
# Die Namen stammen aus dem C64-Vorgängerprojekt und bleiben, damit beide
# HPS-Systeme gleich sind.

package require qsys

set bridges {
	c64_bridge   4 0x00010100 c64_m0
	disk_bridge 14 0x00014000 disk_m0
}

# 1. peripheral_subsys: Pipeline-Brücken an pb_cpu_0.m0, m0 exportieren
load_system peripheral_subsys/peripheral_subsys.qsys
foreach {name aw base export} $bridges {
	if {[lsearch [get_interfaces] $export] >= 0} { remove_interface $export }
	if {[lsearch [get_instances] $name] >= 0} { remove_instance $name }

	add_instance $name altera_avalon_mm_bridge
	set_instance_parameter_value $name DATA_WIDTH             32
	set_instance_parameter_value $name SYMBOL_WIDTH           8
	set_instance_parameter_value $name ADDRESS_UNITS          SYMBOLS
	set_instance_parameter_value $name USE_AUTO_ADDRESS_WIDTH 0
	set_instance_parameter_value $name ADDRESS_WIDTH          $aw
	set_instance_parameter_value $name MAX_BURST_SIZE         1

	add_connection periph_clk.out_clk $name.clk
	add_connection periph_rst_in.out_reset $name.reset
	add_connection pb_cpu_0.m0 $name.s0
	set_connection_parameter_value pb_cpu_0.m0/$name.s0 baseAddress $base

	add_interface $export avalon master
	set_interface_property $export EXPORT_OF $name.m0
	puts "peripheral_subsys: $name (Basis $base, Export $export)"
}
save_system

# 2. qsys_top: die neuen Exporte des Subsystems nach außen führen
load_system qsys_top.qsys
foreach {name aw base export} $bridges {
	if {[lsearch [get_interfaces] $export] >= 0} { remove_interface $export }
	add_interface $export avalon master
	set_interface_property $export EXPORT_OF subsys_periph.$export
	puts "qsys_top: Export $export"
}
save_system
