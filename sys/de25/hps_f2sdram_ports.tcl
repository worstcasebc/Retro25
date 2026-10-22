# SPDX-License-Identifier: GPL-3.0-or-later
# hps_f2sdram_ports.tcl — führt drei DDR-Ports aus qsys_top heraus (P3).
#
# Aufruf (einmal nach tools/fetch_hps.py; ändert sys/hps/qsys_top.qsys):
#     qsys-script --system-file=sys/hps/qsys_top.qsys --script=sys/de25/hps_f2sdram_ports.tcl
#                 --quartus-project=cores/testpattern/quartus/testpattern.qpf
# (--system-file lädt das System; ohne Quartus-Projekt legt qsys-script ein
# Hilfsprojekt neben dem Skript an — irgendein Retro25-Core-Projekt genügt.)
# Die GHRD-Dateien stehen nicht im Repository (Terasic) — deshalb liegt hier
# nur das Rezept, nicht das Ergebnis. Mehrfach ausführbar: vorhandene
# Retro25-Teile werden zuerst entfernt.
#
# Was es baut — MiSTers drei sysmem-Ports (sys/de25/sysmem_de25.v):
#   f2s_vbuf  128 bit  Scaler ascal (Framebuffer)
#   f2s_ram1   64 bit  DDRAM des Cores
#   f2s_ram2   64 bit  ALSA/Palette
# Je eine Avalon-MM Clock Crossing Bridge: Slave-Seite (s0) mit eigenem
# Takt nach außen, Master-Seite (m0) auf clk_100 am AXI4-F2SDRAM
# (subsys_hps.f2sdram_adapter_axi4_sub, 256 bit). Platform Designer erzeugt
# dahinter Arbiter, Breitenanpassung und Avalon->AXI. (Den JTAG-Master
# ext_hps_f2sdram_master entfernt danach hps_slim.tcl, P5.)
# Warum ausdrücklich Clock Crossing Bridges? Der Taktübergang ist so ein
# sichtbarer, FIFO-gepufferter Baustein statt einer automatisch eingefügten
# Anpassung — und die FIFOs fangen Bursts ab.
#
# Adressen: Byte-Adressen, 32 bit = physische HPS-Adresse (P3 Schritt 1).
# sysmem_de25 rechnet MiSTers Wortadresse um und setzt Bit 31
# (0x2000_0000 -> 0xA000_0000, reserviertes Fenster, linux/boot).
# Das harte HPS-IP (agilex_hps) bleibt unverändert -> HPS IO hash sollte
# gleich bleiben (beim Bau mit quartus_pfg prüfen).

package require qsys

set f2s_target  subsys_hps.f2sdram_adapter_axi4_sub
set m_clock     clk_100.out_clk
set m_reset     rst_in.out_reset

# name  Datenbreite
set ports {
	f2s_vbuf 128
	f2s_ram1  64
	f2s_ram2  64
}

foreach {name width} $ports {
	foreach inst [list $name ${name}_clkbr] {
		if {[lsearch [get_instances] $inst] >= 0} { remove_instance $inst }
	}
	foreach i [list ${name} ${name}_clk ${name}_reset] {
		if {[lsearch [get_interfaces] $i] >= 0} { remove_interface $i }
	}

	add_instance $name altera_avalon_mm_clock_crossing_bridge
	set_instance_parameter_value $name DATA_WIDTH          $width
	set_instance_parameter_value $name SYMBOL_WIDTH        8
	set_instance_parameter_value $name ADDRESS_WIDTH       32
	set_instance_parameter_value $name USE_AUTO_ADDRESS_WIDTH 0
	set_instance_parameter_value $name ADDRESS_UNITS       SYMBOLS
	# MiSTer: burstcount 8 bit -> Bursts bis 128 Wörter
	set_instance_parameter_value $name MAX_BURST_SIZE      128
	set_instance_parameter_value $name BURSTCOUNT_WIDTH    8
	# Schreib-Burst passt komplett in den Befehls-FIFO, Lese-Antworten in
	# den Antwort-FIFO (auch wenn der Core gerade nicht abnimmt)
	set_instance_parameter_value $name COMMAND_FIFO_DEPTH  256
	set_instance_parameter_value $name RESPONSE_FIFO_DEPTH 256
	set_instance_parameter_value $name MASTER_SYNC_DEPTH   2
	set_instance_parameter_value $name SLAVE_SYNC_DEPTH    2

	# Master-Seite: clk_100, am F2SDRAM-Adapter, ab Adresse 0 (4 GB)
	add_connection $m_clock $name.m0_clk
	add_connection $m_reset $name.m0_reset
	add_connection $name.m0 $f2s_target
	set_connection_parameter_value $name.m0/$f2s_target baseAddress 0x0

	# Slave-Seite: Takt über eine Clock Bridge von außen — ein direkt
	# exportierter Takteingang gilt nicht als Taktquelle, dann fehlt dem
	# Reset-Synchronizer der s0-Domäne der Takt (qsys-generate: "Cannot find
	# clock for …s0_clk … use a clock bridge"). Reset aus rst_in, Platform
	# Designer synchronisiert ihn in die s0-Domäne.
	add_instance ${name}_clkbr altera_clock_bridge
	set_instance_parameter_value ${name}_clkbr EXPLICIT_CLOCK_RATE 0
	set_instance_parameter_value ${name}_clkbr NUM_CLOCK_OUTPUTS 1
	add_interface ${name}_clk clock sink
	set_interface_property ${name}_clk EXPORT_OF ${name}_clkbr.in_clk
	add_connection ${name}_clkbr.out_clk $name.s0_clk
	add_connection $m_reset $name.s0_reset
	add_interface $name avalon slave
	set_interface_property $name EXPORT_OF $name.s0
}

save_system
