@echo off
rem Kiln Queue setup for Windows. Runs script\windows\setup.ps1 without
rem needing to change PowerShell's execution policy.  Usage: .\setup.cmd --help
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0script\windows\setup.ps1" %*
exit /b %ERRORLEVEL%
