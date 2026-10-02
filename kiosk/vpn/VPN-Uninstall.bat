@echo off
rem Removes the MyTV VPN switcher and closes the VPN (asks for admin rights)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0uninstall-vpn.ps1\"'"
