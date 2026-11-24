#Requires -RunAsAdministrator
<#
  Cree une tache planifiee « ComfyUI Presenton » qui lance run-comfyui-lan.bat
  au demarrage de Windows, meme sans session interactive.

  Usage (PowerShell en administrateur), depuis le dossier portable ComfyUI :
    powershell -ExecutionPolicy Bypass -File install-autostart-task.ps1
    powershell -ExecutionPolicy Bypass -File install-autostart-task.ps1 -ComfyRoot "C:\AI\ComfyUI_windows_portable"

  Alternative (service Windows) : NSSM
    nssm install ComfyUI "C:\AI\ComfyUI_windows_portable\python_embeded\python.exe"
    nssm set ComfyUI AppParameters -s ComfyUI\main.py --listen 0.0.0.0 --port 8188 --windows-standalone-build
    nssm set ComfyUI AppDirectory "C:\AI\ComfyUI_windows_portable"
    nssm start ComfyUI
#>
param(
  [string]$ComfyRoot = (Split-Path -Parent $PSCommandPath),
  [string]$TaskName = "ComfyUI Presenton"
)

$bat = Join-Path $ComfyRoot "run-comfyui-lan.bat"
if (-not (Test-Path $bat)) {
  throw "run-comfyui-lan.bat introuvable dans $ComfyRoot. Copiez d'abord le .bat a la racine du portable."
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute $bat -WorkingDirectory $ComfyRoot
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -StartWhenAvailable `
  -RestartCount 3 `
  -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask `
  -TaskName $TaskName `
  -Action $action `
  -Trigger $trigger `
  -Settings $settings `
  -Principal $principal `
  | Out-Null

Write-Host "Tache planifiee installee : $TaskName"
Write-Host "  Declencheur : au demarrage de Windows"
Write-Host "  Commande    : $bat"
Write-Host "Demarrage immediat : Start-ScheduledTask -TaskName '$TaskName'"
