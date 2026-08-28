@echo off
REM Runs build.ps1 with a per-process execution-policy bypass, so no
REM machine-wide policy change is needed. Any arguments are passed through:
REM   build.cmd -Version 1.5.0 -Clean
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
exit /b %ERRORLEVEL%
