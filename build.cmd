@echo off
setlocal

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" ^
  -NoLogo ^
  -NoProfile ^
  -ExecutionPolicy Bypass ^
  -File "%~dp0bootstrap\windows\main.ps1" ^
  -DataRoot "%~dp0data"
exit /b %errorlevel%
