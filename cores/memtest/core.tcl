# core.tcl — MiSTers SDRAM-Test MemTest (für tools/make_core_qsf.py)
# {CORE} = cores/memtest, {SYS} = sys, relativ zum Quartus-Projektordner.
# Fremdcode in vendor/ (tools/fetch_memtest.py); für Quartus Pro bzw. Agilex 5
# angepasste Kopien in pro/ (Diff je in pro/*.patch).
#
# Feste PLL (ip/pll_memtest): 64 MHz wie clk64 des C64, dazu der SDRAM-Takt
# mit +90 Grad; er geht über das DDIO-Register sys/de25/ip/sdram_clk_ddio
# zum Pin. Messungen und Begründung in README.md.
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/memtest.sv
set_global_assignment -name VERILOG_FILE {CORE}/pro/sdram.v
set_global_assignment -name VERILOG_FILE {CORE}/pro/tester.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/vgaout.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/rnd_vec_gen.v
set_global_assignment -name IP_FILE {CORE}/ip/pll_memtest.ip
set_global_assignment -name IP_FILE {CORE}/ip/pll_memtest_vid.ip
set_global_assignment -name IP_FILE {SYS}/de25/ip/sdram_clk_ddio.ip
set_global_assignment -name SDC_FILE {CORE}/memtest_de25.sdc
set_global_assignment -name SEARCH_PATH {CORE}
