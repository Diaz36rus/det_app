#Requires -Version 5.1
<#
.SYNOPSIS
  Публикует пакеты в C:\detapp-updates и поднимает HTTP на :8080 для LAN-обновлений.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\serve_updates.ps1
  powershell -ExecutionPolicy Bypass -File tools\serve_updates.ps1 -BaseUrl http://192.168.3.2:8080
#>
[CmdletBinding()]
param(
  [string]$PublishDir = 'C:\detapp-updates',
  [string]$BaseUrl = '',
  [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

if (-not $BaseUrl) {
  $ip = $null
  try {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
      Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
      Select-Object -First 1 -ExpandProperty IPAddress)
  } catch {}
  if (-not $ip) {
    $line = ipconfig | Select-String -Pattern 'IPv4' | Select-Object -First 1
    if ($line -match '(\d+\.\d+\.\d+\.\d+)') { $ip = $Matches[1] }
  }
  if (-not $ip) { throw 'Не удалось определить LAN IP. Укажите -BaseUrl http://ВАШ_IP:8080' }
  $BaseUrl = "http://${ip}:$Port"
}

Write-Host "BaseUrl: $BaseUrl" -ForegroundColor Cyan

& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'publish_update.ps1') `
  -PublishDir $PublishDir `
  -BaseUrl $BaseUrl

Write-Host ""
Write-Host "Serving $PublishDir on port $Port … (Ctrl+C to stop)" -ForegroundColor Green
Write-Host "На телефоне: Обновить → URL $BaseUrl/latest.json" -ForegroundColor Yellow
Set-Location $PublishDir
python -m http.server $Port
