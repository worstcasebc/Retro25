@echo off
rem Baut die drei Revisionen des P0-Versuchs und macht daraus die Dateien
rem fuer den HPS-first-Betrieb (siehe p0/README.md).
rem Vorher: "subst Q: <Pfad zu Retro25>" und dieses Skript als
rem Q:\p0\quartus\build_p0.bat starten -- am langen Originalpfad bricht
rem Quartus beim HPS-Design ab (dni::save_checkpoint).
rem
rem Ergebnis in output_files\:
rem   p0_a.hps.jic   QSPI-Flash: I/O-Ring + Bootloader (nur diese flashen)
rem   p0_?.core.rbf  Kern je Revision, laedt U-Boot bzw. Linux
rem   p0_?_pfg.log   Ausgabe von quartus_pfg mit den Pruefsummen (Hashes)
cd /d "%~dp0"
set Q=%QUARTUS_ROOTDIR%\bin64
set SPL=software\u-boot\spl\u-boot-spl-dtb.hex

for %%R in (p0_a p0_b p0_c) do (
    echo ===== %%R: Synthese, Fitter, Assembler
    "%Q%\quartus_sh" --flow compile p0 -c %%R || goto :fehler
)

echo ===== p0_a: .hps.jic und .core.rbf
"%Q%\quartus_pfg" -c output_files\p0_a.sof output_files\p0_a.jic -o device=MT25QU128 -o flash_loader=A5EB013BB23B -o hps_path=%SPL% -o mode=ASX4 -o hps=1 > output_files\p0_a_pfg.log 2>&1 || goto :fehler
for %%R in (p0_b p0_c) do (
    echo ===== %%R: .core.rbf
    "%Q%\quartus_pfg" -c output_files\%%R.sof output_files\%%R.rbf -o hps_path=%SPL% -o hps=1 > output_files\%%R_pfg.log 2>&1 || goto :fehler
)

echo.
echo ===== Pruefsummen (IO hash und HPS IO hash muessen gleich sein):
findstr /i "hash" output_files\p0_a_pfg.log output_files\p0_b_pfg.log output_files\p0_c_pfg.log
echo.
dir /b output_files\*.jic output_files\*.rbf
pause
exit /b 0

:fehler
echo FEHLER -- Ausgabe oben bzw. output_files\*_pfg.log ansehen.
pause
exit /b 1
