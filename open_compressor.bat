@echo off
setlocal
cd /d "%~dp0"
:: Launch without leaving a console window. Windows PowerShell and WinForms are built in.
start "" powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0compressor-gui.ps1"
