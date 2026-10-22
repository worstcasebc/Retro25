@echo off
rem Schreibt p0_a.hps.jic ins QSPI-Flash (HPS-first: I/O-Ring + Bootloader).
rem Achtung: ueberschreibt das C64-Design im Flash. Zurueck zum C64:
rem C64-DE25\quartus_hps\flash_program.bat (dessen .jic).
rem Voraussetzung wie beim C64: SW5 im AS-Modus (SW5.1 OFF, SW5.2 und SW5.3
rem ON), Board an, USB-Blaster verbunden.
cd /d "%~dp0"
"%QUARTUS_ROOTDIR%\bin64\quartus_pgm" -m jtag -c 1 -o "pvi;output_files\p0_a.hps.jic"
pause
