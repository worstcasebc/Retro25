@echo off
rem build_core.bat ^<core^> [^<revision^>] -- baut einen Retro25-Core und erzeugt
rem <revision>.core.rbf (Revision: Vorgabe = Core, z. B. sdram486test_p090).
rem Vorher einmalig: "subst Q: <Pfad zu Retro25>", python tools\fetch_hps.py
rem <GHRD-Ordner> sys\hps, python tools\make_core_qsf.py <core> (siehe README.md).
rem Aufruf ueber den kurzen Pfad: Q:\tools\build_core.bat testpattern
rem
rem Ergebnis in Q:\cores\<core>\quartus\output_files\:
rem   <core>.core.rbf   Kern, laedt Linux (p0_switch.py) oder U-Boot
rem   <core>_pfg.log    Ausgabe von quartus_pfg mit den Pruefsummen
rem Der "HPS IO hash" muss dem des Flash-Inhalts gleichen (P0: 474D6C20...).
setlocal
if "%~1"=="" (echo Aufruf: build_core.bat ^<core^> & exit /b 1)
set CORE=%~1
set REV=%~2
if "%REV%"=="" set REV=%CORE%
set Q=%QUARTUS_ROOTDIR%\bin64
cd /d "%~dp0..\cores\%CORE%\quartus" || exit /b 1
set SPL=..\..\..\sys\hps\software\u-boot\spl\u-boot-spl-dtb.hex

echo ===== %REV%: Synthese, Fitter, Assembler
"%Q%\quartus_sh" --flow compile %CORE% -c %REV% || goto :fehler
echo ===== %REV%: .core.rbf
"%Q%\quartus_pfg" -c output_files\%REV%.sof output_files\%REV%.rbf -o hps_path=%SPL% -o hps=1 > output_files\%REV%_pfg.log 2>&1 || goto :fehler
findstr /i "hash" output_files\%REV%_pfg.log
dir /b output_files\*.core.rbf
pause
exit /b 0

:fehler
echo FEHLER -- Ausgabe oben bzw. output_files ansehen.
pause
exit /b 1
