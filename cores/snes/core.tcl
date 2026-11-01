# core.tcl — MiSTers SNES-Core für tools/make_core_qsf.py
# {CORE} = cores/snes, {SYS} = sys, relativ zum Quartus-Projektordner.
# Fremdcode in vendor/ (tools/fetch_snes.py); angepasste Kopien in pro/
# (Diff je in *.patch bzw. *.subst.json); rtl/bram.vhd und rtl/mlab.vhd
# sind eigene Ersatzdateien (inferierte RAMs, wie beim MegaDrive).
# Takt: feste PLL ip/pll_snes (nur NTSC, wie NES), SDRAM_CLK = clk_mem +90
# Grad über sys/de25/ip/sdram_clk_ddio.
# Dateiliste = vendor/files.qip samt Unter-.qip, ausgeschrieben.
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/65C816/P65816_pkg.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/65C816/AddrGen.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/65C816/BCDAdder.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/65C816/AddSubBCD.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/65C816/ALU.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/65C816/MCode.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/65C816/P65C816.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SPC700/SPC700_pkg.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SPC700/AddrGen.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SPC700/AddSub.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SPC700/ALU.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SPC700/BCDAdj.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SPC700/MCode.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SPC700/MulDiv.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SPC700/SPC700.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/chip/CX4/CX4.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/CX4/cx4cache.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/chip/CX4/CX4Map.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/chip/DSP/DSPn.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/chip/DSP/DSP_LHRomMap.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/DSP/OBC1.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/SDD1/InputMgr.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/SDD1/Decoder.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/SDD1/SDD1.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/SDD1/SDD1Map.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/GSU/GSU.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/GSU/GSU_PKG.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/GSU/GSUMap.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/SA1/SA1.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/SA1/SA1DIV.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/SA1/SA1MULT.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/SA1/SA1Map.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/SPC7110/SPC7110.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/SPC7110/SPC7110_DEC.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/SPC7110/SPC7110_DEC_PKG.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/SPC7110/SPC7110_FIFO.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/SPC7110/SPC7110_MULDIV.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/SPC7110/SPC7110Map.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/Sufami/SufamiMap.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/BSX/BSX_MCC.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/BSX/BSX_DP.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/chip/BSX/BSX_BS.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/BSX/BSXMap.vhd
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/chip/MSU1/MSU.sv
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/chip/MSU1/msu_audio.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/chip/MSU1/msu_fifo.v
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/chip/MSU1/msu_data_store.sv
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/RTC4513.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/chip/SRTC.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/CEGen.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SWRAM.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SMP.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/PPU_PKG.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/PPU.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/CPU.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/DSP_PKG.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/DSP.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SNES.vhd
set_global_assignment -name VERILOG_FILE {CORE}/pro/rtl/main.v -hdl_version VERILOG_2001
# main.v benutzt "do" als Signalnamen (in SystemVerilog ein Schlüsselwort, 19645)
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/cheatcodes.sv
set_global_assignment -name VHDL_FILE {CORE}/rtl/bram.vhd
set_global_assignment -name VHDL_FILE {CORE}/rtl/mlab.vhd
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/ddram.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/sdram.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/ioport.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/lightgun.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/miracle.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/hps_ext.v
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/savestates.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/savestates_regs.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/savestates_map.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/savestates_sa1.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/savestate_ui.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/sni.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/uart.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/SNES.sv
set_global_assignment -name IP_FILE {CORE}/ip/pll_snes.ip
set_global_assignment -name IP_FILE {SYS}/de25/ip/sdram_clk_ddio.ip
set_global_assignment -name SDC_FILE {CORE}/snes_de25.sdc
# `include "build_id.v" (Datum im OSD), cores/snes/build_id.v
set_global_assignment -name SEARCH_PATH {CORE}
# Makro aus MiSTers SNES.qsf (kleinerer Bildpuffer des Scalers)
set_global_assignment -name VERILOG_MACRO "MISTER_SMALL_VBUF=1"
