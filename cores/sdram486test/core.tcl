# core.tcl — SDRAM-Test für den z486-Controller (P5 Z3; für tools/make_core_qsf.py)
# {CORE} = cores/sdram486test, {SYS} = sys, relativ zum Quartus-Projektordner.
#
# Rahmen und Anzeige aus MiSTers MemTest (cores/memtest/vendor), geprüft wird
# upstreams z486-Controller (cores/z486/pro/src/memory/sdram.v) mit dem
# eigenen Prüfablauf rtl/tester486.v bei 85 MHz über 128 MB (beide Chips).
# PLL: Grundprojekt mit ip/pll_486.ip (Platzhalter); die Revisionen
# sdram486test_pNNN (make_variants.py) setzen ip/pNNN/pll_486.ip ein.
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/rtl/sdram486test.sv
set_global_assignment -name VERILOG_FILE {CORE}/rtl/tester486.v
set_global_assignment -name VERILOG_FILE {CORE}/../z486/pro/src/memory/sdram.v
set_global_assignment -name VERILOG_FILE {CORE}/../memtest/vendor/rtl/vgaout.v
set_global_assignment -name IP_FILE {CORE}/ip/pll_486.ip
set_global_assignment -name IP_FILE {CORE}/../memtest/ip/pll_memtest_vid.ip
set_global_assignment -name IP_FILE {SYS}/de25/ip/sdram_clk_ddio.ip
set_global_assignment -name SDC_FILE {CORE}/sdram486test.sdc
set_global_assignment -name SEARCH_PATH {CORE}
