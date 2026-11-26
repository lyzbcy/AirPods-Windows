# Manual one-shot metadata probe; does not launch the product.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Address)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'BatteryObservation.psm1') -Force
Get-OsBatteryObservation -Address $Address | ConvertTo-Json -Compress
