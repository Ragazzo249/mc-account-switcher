@echo off
rem Minecraft アカウント切り替え GUI を起動する
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0mc-switcher.ps1"
