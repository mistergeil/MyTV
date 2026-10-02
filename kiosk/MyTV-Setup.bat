@echo off
rem ============================================================
rem  MyTV - one-time setup: opens the MyTV Chrome profile
rem  normally (not fullscreen) so you can install Tampermonkey
rem  and the MyTV Helper script.
rem ============================================================
set "CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" set "CHROME=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" set "CHROME=%LocalAppData%\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" (
  echo Google Chrome not found. Please install it from https://www.google.com/chrome/
  pause
  exit /b 1
)

start "" "%CHROME%" ^
  --user-data-dir="%LocalAppData%\MyTV-Chrome" ^
  --no-first-run ^
  --no-default-browser-check ^
  "https://chromewebstore.google.com/detail/tampermonkey/dhdgffkkebhmkfjojejmpbldmpobfkfo" ^
  "https://mistergeil.github.io/MyTV/kiosk/"
