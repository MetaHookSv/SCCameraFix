@echo off
setlocal
set "Configuration=Release"
call "%~dp0build-SCCameraFix-x86.bat" %*
exit /b %errorlevel%
