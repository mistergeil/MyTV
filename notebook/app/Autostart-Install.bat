@echo off
rem ============================================================
rem  MyTV - start the TV automatically when Windows logs in
rem  (copies MyTV-Kiosk.bat into your Startup folder)
rem ============================================================
copy /Y "%~dp0MyTV-Kiosk.bat" "%AppData%\Microsoft\Windows\Start Menu\Programs\Startup\MyTV-Kiosk.bat" >nul
if errorlevel 1 ( echo Failed. & pause & exit /b 1 )
rem Never sleep / turn off the screen while plugged in
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
echo Done. MyTV will start automatically after login.
echo To undo: run Autostart-Remove.bat
pause
