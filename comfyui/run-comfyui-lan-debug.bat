@echo off
cd /d "%~dp0"
call "%~dp0run-comfyui-lan.bat"
echo.
echo ComfyUI s'est arrete. Cette fenetre reste ouverte pour lire les erreurs.
pause
