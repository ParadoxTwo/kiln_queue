@echo off
rem Starts Kiln Queue on Windows. Runs script\windows\dev.ps1 without
rem needing to change PowerShell's execution policy.  Usage: .\dev.cmd --help
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0script\windows\dev.ps1" %*
exit /b %ERRORLEVEL%
