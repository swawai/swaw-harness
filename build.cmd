@echo off
setlocal

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" ^
  -NoLogo ^
  -NoProfile ^
  -ExecutionPolicy Bypass ^
  -File "%~dp0bootstrap\windows\main.ps1" ^
  -RepositoryDataRoot "%~dp0data.repo"
exit /b %errorlevel%
