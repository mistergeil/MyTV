@echo off
rem ============================================================
rem  MyTV - start the TV (Chrome kiosk, fullscreen, autoplay)
rem  Exit: Alt+F4
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
  --kiosk ^
  --autoplay-policy=no-user-gesture-required ^
  --no-first-run ^
  --no-default-browser-check ^
  --disable-session-crashed-bubble ^
  --disable-features=Translate,TranslateUI ^
  --overscroll-history-navigation=0 ^
  --disable-pinch ^
  --disable-direct-composition-video-overlays ^
  "https://mistergeil.github.io/MyTV/?kiosk=1"
