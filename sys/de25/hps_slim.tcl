# SPDX-License-Identifier: GPL-3.0-or-later
# hps_slim.tcl — entfernt aus dem HPS-System die Demo- und Debug-Teile von
# Terasics GHRD, die MiSTer nicht braucht (P5, Platz für den z486).
#
# Aufruf: von tools/fetch_hps.py nach hps_f2sdram_ports.tcl (oder von Hand,
# im Ordner sys/hps):
#     qsys-script --system-file=qsys_top.qsys --script=../de25/hps_slim.tcl
#                 --quartus-project=<Wegwerf-Projekt>
# Danach qsys_top neu erzeugen (fetch_hps.py: generate()).
# Mehrfach ausführbar: schon Entferntes wird übersprungen.
#
# Was entfällt (Menü-Core, Stand P4: HPS-System ~14k ALMs, 148 M20K):
#   ocm                          256 KB On-Chip-RAM an hps2fpga (GHRD-Demo),
#                                128 M20K
#   subsys_debug                 drei JTAG-Master (System Console) auf ocm,
#                                F2SDRAM und HPS-Speicher
#   ace5lite_cache_coherency_translator_0
#                                nur für den JTAG-Master zum HPS-Speicher
#                                (fpga2hps), ~2,6k ALMs mit Bus-Logik
#   ext_hps_f2sdram_master       Adressfenster des JTAG-Masters zum F2SDRAM
#   FPGA->HPS-Bridge (fpga2hps)  im HPS-IP abgeschaltet (f2s_data_width 0):
#                                ohne Gegenstelle verlangt Quartus sonst eine
#                                Verbindung (24265/129015)
# Analogie: Aus dem Werkstattwagen fliegen die Vorführteile und das
# Diagnosegerät; Motor (HPS), Lenkung (LW-Bridge) und Tank (F2SDRAM) bleiben.
#
# Es bleiben: subsys_hps (LW-Bridge, F2SDRAM, hps2fpga unbenutzt),
# subsys_periph an der LW-Bridge, die DDR-Ports f2s_vbuf/f2s_ram1/f2s_ram2.
# Zum Debuggen bleibt Signal Tap; System-Console-Tests über JTAG-Master gehen
# danach nicht mehr (dafür fetch_hps.py ohne dieses Skript laufen lassen).

package require qsys

# 1. HPS-Subsystem: FPGA->HPS-Bridge aus (agilex_hps ist eine generische
#    Komponente: Parameter über load_component in der .ip-Datei) und ihre
#    drei Exporte entfernen
load_system hps_subsys/hps_subsys.qsys
load_component agilex_hps
if {[get_component_parameter_value f2s_data_width] != 0} {
	set_component_parameter_value f2s_data_width 0
	save_component
	puts "agilex_hps: f2s_data_width 0 (FPGA->HPS-Bridge aus)"
}
foreach i {fpga2hps fpga2hps_clk fpga2hps_rst} {
	if {[lsearch [get_interfaces] $i] >= 0} {
		remove_interface $i
		puts "hps_subsys: Export $i entfernt"
	}
}
save_system

# 2. qsys_top: Demo-/Debug-Teile raus, Takt/Reset der Bridge abklemmen
load_system qsys_top.qsys
foreach c [get_connections] {
	if {[regexp {subsys_hps\.fpga2hps_(clk|rst)$} $c]} {
		remove_connection $c
		puts "entfernt: Verbindung $c"
	}
}
foreach inst {ocm subsys_debug ace5lite_cache_coherency_translator_0 ext_hps_f2sdram_master} {
	if {[lsearch [get_instances] $inst] >= 0} {
		remove_instance $inst
		puts "entfernt: $inst"
	}
}
# Rest eines früheren Versuchs (Bridge nach außen geführt)
if {[lsearch [get_interfaces] fpga2hps] >= 0} {
	remove_interface fpga2hps
	puts "entfernt: Export fpga2hps"
}
save_system
