# core.tcl — MiSTers C64-Core (für tools/make_core_qsf.py)
# {CORE} = cores/c64, {SYS} = sys, relativ zum Quartus-Projektordner.
# Fremdcode in vendor/ (tools/fetch_c64.py, ohne ROMs); für Quartus Pro bzw.
# Agilex 5 angepasste Kopien in pro/ (Diff je in *.patch).
#
# ROMs: vor dem Bau `python tools/make_c64_roms.py` — schreibt die .mif aus
# roms/ nach cores/c64/quartus/rtl/ (MiSTers Pfade sind relativ zum Projekt).
# Takt: feste PLL ip/pll_c64 (nur PAL), SDRAM_CLK = clk64 + 90 Grad über
# sys/de25/ip/sdram_clk_ddio.
# Dateiliste = vendor/files.qip samt Unter-.qip, ausgeschrieben; Dateien mit
# Anpassung aus pro/.
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/sid/sid_top.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/sid/sid_voice.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/sid/sid_tables.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/sid/sid_filter.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/sid/sid_envelope.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/sid/sid_dac.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/opl3/opl3.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/opl3/opl3fm.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/opl3/opl3seq.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/opl3/compressor.sv
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/opl3/NextZ80Reg.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/opl3/NextZ80CPU.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/opl3/NextZ80ALU.v
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/iec_drive/iec_drive.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/iec_drive/c1541_multi.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/iec_drive/c1541_drv.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/iec_drive/c1541_gcr.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/iec_drive/c1541_direct_gcr.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/iec_drive/c1541_track.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/iec_drive/c1541_logic.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/iec_drive/c1581_multi.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/iec_drive/c1581_drv.sv
set_global_assignment -name VERILOG_FILE {CORE}/pro/rtl/iec_drive/fdc1772.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/iec_drive/floppy.v
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/iec_drive/iecdrv_via6522.vhd
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/iec_drive/iecdrv_mos8520.v
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/iec_drive/iecdrv_misc.sv
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/iec_drive/lfsr.v
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/t65/T65_Pack.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/t65/T65_ALU.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/t65/T65_MCode.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/t65/T65.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/cpu_6510.vhd
set_global_assignment -name VERILOG_FILE {CORE}/pro/rtl/mos6526.v
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/rtcF83.sv
set_global_assignment -name VERILOG_FILE {CORE}/pro/sdram.v
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/dprom.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/spram.vhd
set_global_assignment -name VERILOG_FILE {CORE}/pro/rtl/cartridge.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/reu.v
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/am29f040.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/c1530.sv
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/c1351.v
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/video_sync.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/video_vicII_656x.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/fpga64_rgbcolor.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/fpga64_keyboard.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/fpga64_buslogic.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/fpga64_sid_iec.vhd
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/drv_overlay.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/tap_scanner.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/tap_time_map.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/tape_counter.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/tape_subsystem.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/c64.sv
# eigene Module (Testbench je in tb/)
set_global_assignment -name VERILOG_FILE {CORE}/rtl/iecdrv_bitmem.v
set_global_assignment -name VERILOG_FILE {CORE}/rtl/opl3_mem.v
set_global_assignment -name IP_FILE {CORE}/ip/pll_c64.ip
set_global_assignment -name IP_FILE {SYS}/de25/ip/sdram_clk_ddio.ip
set_global_assignment -name SDC_FILE {CORE}/c64_de25.sdc
# $readmemh der OPL3 (opl3prg.mem, sin_tab_full.mem, exp_tab.mem)
set_global_assignment -name SEARCH_PATH {CORE}/vendor/rtl/opl3
set_global_assignment -name SEARCH_PATH {CORE}
