# SPDX-License-Identifier: GPL-3.0-or-later
# f2sdram.tcl — Zugriff auf das HPS-DDR über F2SDRAM aus System Console (P3).
#
# Weg: JTAG-Master "hps_f2sdram" (jtag_subsys im GHRD) -> Adressfenster
# ext_hps_f2sdram_master (4 GB ab 0) -> f2sdram_adapter -> HPS-F2SDRAM.
# Gegenstelle auf dem Board: p3/linux/f2sdram_probe.py.
#
# In System Console:
#   source <Pfad>/p3/sc/f2sdram.tcl
#   f2s_scan  0x12345000 3      ;# mit allen Mastern lesen (Erkennen)
#   f2s_open  2                 ;# Master Nummer 2 belegen
#   f2s_read  0x12345000 2      ;# 2 Wörter (32 bit) lesen
#   f2s_write 0x12345100 0xCAFE0001
#   f2s_close
# Nur an Adressen schreiben, die f2sdram_probe.py nennt — alles andere ist
# Arbeitsspeicher von Linux.

# Ohne verknüpftes Design heißen die Master nur phy_0..phy_2. Laut
# qsys_top.qsys gibt es drei: fpga_m (nur On-Chip-RAM ab 0x40000),
# hps_m (F2H, kohärent) und hps_f2sdram (F2SDRAM). f2s_scan zeigt, welcher
# welcher ist; f2s_open <Nummer> belegt dann einen davon.

proc f2s_paths {} {
	return [lsort [get_service_paths master]]
}

# Liest mit jedem Master n Wörter ab addr (nur lesen, gefahrlos).
proc f2s_scan {addr {n 3}} {
	set i 0
	foreach p [f2s_paths] {
		set c [claim_service master $p retro25_scan]
		if {[catch {master_read_32 $c $addr $n} vals]} { set vals "Fehler: $vals" }
		close_service master $c
		puts "  $i: $vals    ($p)"
		incr i
	}
}

proc f2s_open {{idx ""}} {
	global f2s
	set paths [f2s_paths]
	if {$idx eq ""} {
		set i 0
		foreach p $paths { puts "  $i: $p"; incr i }
		puts "Nummer wählen: f2s_open <Nummer> (f2s_scan hilft beim Erkennen)"
		return
	}
	set p [lindex $paths $idx]
	set f2s [claim_service master $p retro25]
	puts "belegt: $p"
}

proc f2s_read {addr {n 1}} {
	global f2s
	set vals [master_read_32 $f2s $addr $n]
	set i 0
	foreach v $vals {
		puts [format "  0x%09X: %s" [expr {$addr + 4 * $i}] $v]
		incr i
	}
}

proc f2s_write {addr val} {
	global f2s
	master_write_32 $f2s $addr [list $val]
	puts [format "  0x%09X <- %s" $addr $val]
}

proc f2s_close {} {
	global f2s
	close_service master $f2s
	unset f2s
}
