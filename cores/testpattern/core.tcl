# core.tcl — Dateien und Einstellungen des Testcores (für tools/make_core_qsf.py)
# {CORE} = cores/testpattern, relativ zum Quartus-Projektordner.
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/testpattern.sv
set_global_assignment -name VERILOG_FILE {CORE}/ddr_test.v
set_global_assignment -name IP_FILE {CORE}/ip/pll_tp.ip
set_global_assignment -name SEARCH_PATH {CORE}
