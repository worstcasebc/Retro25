# core.tcl — MiSTers NES-Core (für tools/make_core_qsf.py)
# {CORE} = cores/nes, {SYS} = sys, relativ zum Quartus-Projektordner.
# Fremdcode in vendor/ (tools/fetch_nes.py); für Quartus Pro bzw. Agilex 5
# angepasste Kopien in pro/ (Diff je in *.patch).
# Takt: feste PLL ip/pll_nes (nur NTSC, tools/make_iopll.py), SDRAM_CLK =
# clk85 + 90 Grad über sys/de25/ip/sdram_clk_ddio.
# Dateiliste = vendor/files.qip samt Unter-.qip, ausgeschrieben; Dateien mit
# Anpassung aus pro/, rtl/dpram.vhd ist ein eigener Ersatz (inferierte RAMs).

# Paket zuerst: Quartus Pro übersetzt in Listenreihenfolge (Mapper importieren es)
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/regs_savestates.sv
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/t65/T65_Pack.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/t65/T65_ALU.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/t65/T65_MCode.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/t65/T65.vhd
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/mappers/VRC.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/mappers/Sunsoft.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/mappers/Sachen.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/mappers/Namco.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/mappers/MMC5.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/mappers/MMC3.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/mappers/MMC2.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/mappers/MMC1.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/mappers/misc.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/mappers/JYCompany.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/mappers/Mapper99.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/mappers/generic.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/mappers/FDS.sv
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SOUND/OPLL/VM2413/attacktable.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/SOUND/OPLL/VM2413/controller.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/SOUND/OPLL/VM2413/envelopegenerator.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SOUND/OPLL/VM2413/envelopememory.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SOUND/OPLL/VM2413/feedbackmemory.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SOUND/OPLL/VM2413/lineartable.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SOUND/OPLL/VM2413/operator.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SOUND/OPLL/VM2413/opll.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SOUND/OPLL/VM2413/outputgenerator.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SOUND/OPLL/VM2413/outputmemory.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SOUND/OPLL/VM2413/phasegenerator.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SOUND/OPLL/VM2413/phasememory.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SOUND/OPLL/VM2413/registermemory.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SOUND/OPLL/VM2413/sinetable.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SOUND/OPLL/VM2413/slotcounter.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SOUND/OPLL/VM2413/temporalmixer.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SOUND/OPLL/VM2413/vm2413.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/SOUND/OPLL/VM2413/voicememory.vhd
set_global_assignment -name VHDL_FILE {CORE}/pro/rtl/SOUND/OPLL/VM2413/voicerom.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/SOUND/OPLL/eseopll.vhd
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/sdram.sv
set_global_assignment -name VHDL_FILE {CORE}/rtl/dpram.vhd
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/ddram.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/EEPROM_24C0x.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/cheatcodes.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/miracle.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/keyboard.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/zapper.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/cart.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/video.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/composite_decoder.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/composite_board.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/vendor/rtl/composite_crop.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/ppu.sv
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/apu.sv
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/bus_savestates.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/statemanager.vhd
set_global_assignment -name VHDL_FILE {CORE}/vendor/rtl/savestates.vhd
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/savestate_ui.sv
# nes.v als SystemVerilog: pro/ ergänzt "import regs_savestates::*;"
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/rtl/nes.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/dsp.v
set_global_assignment -name VERILOG_FILE {CORE}/vendor/rtl/compat.v
set_global_assignment -name SYSTEMVERILOG_FILE {CORE}/pro/NES.sv
set_global_assignment -name IP_FILE {CORE}/ip/pll_nes.ip
set_global_assignment -name IP_FILE {SYS}/de25/ip/sdram_clk_ddio.ip
set_global_assignment -name SDC_FILE {CORE}/nes_de25.sdc
# `include "build_id.v" (Datum im OSD), cores/nes/build_id.v
set_global_assignment -name SEARCH_PATH {CORE}
