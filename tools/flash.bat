@echo off
rem SPDX-License-Identifier: GPL-3.0-or-later
rem flash.bat [^<core^>] -- schreibt ^<core^>.hps.jic (make_flash.bat) ins
rem QSPI-Flash des DE25-Nano. Vorgabe: menu.
rem Vorher: Board stromlos, SW5 in den AS-Modus (SW5.1 OFF, SW5.2 und SW5.3
rem ON), USB-Blaster (USB-Buchse am Board) verbunden, Board einschalten.
rem Danach Board aus- und wieder einschalten.
setlocal
set CORE=%~1
if "%CORE%"=="" set CORE=menu
cd /d "%~dp0..\cores\%CORE%\quartus\output_files" || exit /b 1
"%QUARTUS_ROOTDIR%\bin64\quartus_pgm" -m jtag -c 1 -o "pvi;%CORE%.hps.jic"
