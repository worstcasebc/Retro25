# core.tcl — MiSTers MegaDrive-Core (Nuked-MD) für tools/make_core_qsf.py
# {CORE} = cores/megadrive, {SYS} = sys, relativ zum Quartus-Projektordner.
# Fremdcode in vendor/ (tools/fetch_megadrive.py); angepasste Kopien in pro/
# (Diff je in *.patch); rtl/bram.vhd und rtl/mlab.vhd sind eigene Ersatzdateien
# (inferierte RAMs, Testbench tb/tb_md_bram.v), rtl/vram_ip.v ersetzt
# rtl/ram_md.v (altera_syncram mit Byte-Freigaben, tb/tb_md_vram_ip.v).
# Takt: feste PLL ip/pll_md (nur NTSC), SDRAM_CLK über sys/de25/ip/sdram_clk_ddio.
# Dateiliste = vendor/files.qip samt Unter-.qip, ausgeschrieben.
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/VM2413/attacktable.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/VM2413/controller.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/VM2413/envelopegenerator.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/VM2413/envelopememory.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/VM2413/feedbackmemory.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/VM2413/lineartable.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/VM2413/operator.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/VM2413/outputgenerator.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/VM2413/outputmemory.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/VM2413/phasegenerator.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/VM2413/phasememory.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/VM2413/registermemory.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/VM2413/sinetable.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/VM2413/slotcounter.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/VM2413/temporalmixer.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/VM2413/voicememory.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/VM2413/voicerom.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/VM2413/vm2413.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/VM2413/opll.vhd
set_global_assignment -name VHDL_FILE {CORE}/rtl/mlab.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SVP/SSP160x.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SVP/SSP160x_PKG.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SVP/SVP.vhd
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/tmss.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/vram.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/ym_lib.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/ym3438_ch.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/ym3438_detune.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/ym3438_eg.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/ym3438_fsm.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/ym3438_io.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/ym3438_lfo.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/ym3438_op.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/ym3438_pg.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/ym3438_prescaler.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/ym3438_regs.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/ym3438.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/ym6045.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/ym6046.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/ym7101.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/z80.v
set_global_assignment -name VERILOG_FILE {CORE}/pro/rtl/nuked-md/68k.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/fc1004.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/nuked-md/md_board.v
set_global_assignment -name VHDL_FILE {CORE}/rtl/bram.vhd
set_global_assignment -name VERILOG_FILE {CORE}/rtl/vram_ip.v
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/sdram.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/EEPROM_STM95.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/EEPROM_24CXX.sv
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/audio_iir_filter.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/genesis_lpf.v
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/CEGen.vhd
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/cheatcodes.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/audio_cond.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/video_cond.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/cofi.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/lightgun.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/pad_io.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/multitap_sms.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/teamplayer.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/fourway.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/md_io.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/cartridge.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/md_plus.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/mdp_audio.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/hps_ext.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/saturn_keyboard.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/MegaDrive.sv
set_global_assignment -name IP_FILE {CORE}/ip/pll_md.ip
set_global_assignment -name IP_FILE {SYS}/de25/ip/sdram_clk_ddio.ip
set_global_assignment -name SDC_FILE {CORE}/megadrive_de25.sdc
# `include "build_id.v" (Datum im OSD), cores/megadrive/build_id.v
set_global_assignment -name SEARCH_PATH {CORE}
# Makros aus MiSTers MegaDrive.qsf (md_board.v: Cheat-Ports, externe Takte)
set_global_assignment -name VERILOG_MACRO "M68K_CHEAT=1"
set_global_assignment -name VERILOG_MACRO "Z80_CHEAT=1"
set_global_assignment -name VERILOG_MACRO "EXT_CLOCKS=1"
