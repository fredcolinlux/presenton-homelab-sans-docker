#Requires -RunAsAdministrator
<#
  Autorise le port TCP 8188 (ComfyUI) uniquement depuis le reseau local.
  Ajustez -RemoteAddress pour correspondre a VOTRE reseau local
  (exemple courant : 192.168.1.0/24).
#>
param(
  [string]$RemoteAddress = "192.168.1.0/24",
  [int]$Port = 8188,
  [string]$Name = "ComfyUI Presenton LAN 8188"
)

Get-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule

New-NetFirewallRule `
  -DisplayName $Name `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort $Port `
  -RemoteAddress $RemoteAddress `
  -Profile Private,Domain `
  | Out-Null

Write-Host "Regle pare-feu installee : $Name"
Write-Host "  Inbound TCP $Port uniquement depuis $RemoteAddress (profils Private/Domain)."
Get-NetFirewallRule -DisplayName $Name | Format-List DisplayName, Enabled, Direction, Action, Profile
