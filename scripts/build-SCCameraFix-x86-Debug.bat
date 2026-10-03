@echo off
setlocal
set "Configuration=Debug"
call "%~dp0build-SCCameraFix-x86.bat" %*
exit /b %errorlevel%
