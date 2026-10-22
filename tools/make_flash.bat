@echo off
rem SPDX-License-Identifier: GPL-3.0-or-later
rem make_flash.bat [^<core^>] -- erzeugt aus einem gebauten Core die Datei fuers
rem QSPI-Flash (HPS-first: I/O-Ring + HPS-Bootloader). Vorgabe: menu.
rem Voraussetzung: Q:\tools\build_core.bat ^<core^> lief durch.
rem Aufruf ueber den kurzen Pfad: Q:\tools\make_flash.bat
rem
rem Ergebnis: Q:\cores\<core>\quartus\output_files\<core>.hps.jic
rem Welcher Core den I/O-Ring liefert, ist gleich, solange der "HPS IO hash"
rem passt -- alle Retro25-Cores haben dasselbe HPS-System (wie p0_a.hps.jic
rem aus p0\quartus\build_p0.bat, dem in P0 erprobten Weg).
rem Flashen: Q:\tools\flash.bat ^<core^>
setlocal
set CORE=%~1
if "%CORE%"=="" set CORE=menu
set Q=%QUARTUS_ROOTDIR%\bin64
cd /d "%~dp0..\cores\%CORE%\quartus\output_files" || exit /b 1
set SPL=..\..\..\..\sys\hps\software\u-boot\spl\u-boot-spl-dtb.hex
if not exist %CORE%.sof (echo %CORE%.sof fehlt -- erst build_core.bat %CORE% & exit /b 1)

"%Q%\quartus_pfg" -c %CORE%.sof %CORE%.jic -o device=MT25QU128 -o flash_loader=A5EB013BB23B -o hps_path=%SPL% -o mode=ASX4 -o hps=1 > %CORE%_jic.log 2>&1 || goto :fehler
findstr /i "hash" %CORE%_jic.log
dir /b %CORE%.hps.jic
exit /b 0

:fehler
echo FEHLER -- %CORE%_jic.log ansehen.
exit /b 1
