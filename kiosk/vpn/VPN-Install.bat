@echo off
rem Installs the MyTV VPN switcher (asks for admin rights)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0install-vpn.ps1\"'"
