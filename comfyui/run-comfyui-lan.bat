@echo off
REM Place this file in the ComfyUI portable root (next to python_embeded and run_nvidia_gpu.bat).
REM Listens on all interfaces, port 8188, so the Presenton host can reach it on the LAN.
cd /d "%~dp0"
if not exist "python_embeded\python.exe" (
  echo python_embeded\python.exe introuvable. Copiez ce .bat a la racine de ComfyUI_windows_portable.
  exit /b 1
)
.\python_embeded\python.exe -s ComfyUI\main.py --listen 0.0.0.0 --port 8188 --windows-standalone-build
