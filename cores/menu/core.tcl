# core.tcl — MiSTers Menü-Core (für tools/make_core_qsf.py)
# {CORE} = cores/menu, relativ zum Quartus-Projektordner. Fremdcode in
# vendor/ (tools/fetch_menu.py); für Quartus Pro angepasste Kopien in pro/
# (Diff je in pro/*.patch).
set_global_assignment -name VERILOG_MACRO "MENU_CORE=1"
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/menu.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/sdram.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/ddram.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/console_out.sv
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/lfsr.v
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/cos.sv
set_global_assignment -name IP_FILE {CORE}/ip/pll_menu.ip
set_global_assignment -name SEARCH_PATH {CORE}
