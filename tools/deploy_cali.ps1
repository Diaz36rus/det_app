#Requires -Version 5.1
<#
.SYNOPSIS
  Деплой API на Cali по SSH-ключу (без веб-консоли Selectel).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\deploy_cali.ps1
#>
[CmdletBinding()]
param(
  [string]$HostName = '135.106.186.90',
  [string]$User = 'root',
  [string]$Branch = 'ui-studio-polish',
  [string]$KeyPath = ''
)

$ErrorActionPreference = 'Stop'
if (-not $KeyPath) {
  $KeyPath = Join-Path $env:USERPROFILE '.ssh\id_ed25519'
}
$sshCandidates = @(
  'C:\Program Files\Git\usr\bin\ssh.exe',
  'C:\Windows\System32\OpenSSH\ssh.exe'
)
$ssh = $sshCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ssh) { throw 'ssh.exe not found (install Git for Windows or OpenSSH Client)' }
if (-not (Test-Path $KeyPath)) { throw "SSH key missing: $KeyPath" }

function Invoke-Remote([string]$Cmd) {
  Write-Host "==> $Cmd" -ForegroundColor Cyan
  & $ssh -i $KeyPath -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${User}@${HostName}" $Cmd
  if ($LASTEXITCODE -ne 0) { throw "remote failed: $Cmd" }
}

Invoke-Remote "cd /opt/det-app-src && git fetch origin && git checkout $Branch && git pull origin $Branch"
Invoke-Remote "cp -r /opt/det-app-src/server/. /opt/det-app/"
Invoke-Remote "cd /opt/det-app && docker compose up -d --build"
Start-Sleep -Seconds 6
Write-Host '==> health' -ForegroundColor Cyan
curl.exe -s "http://api.det-app.ru/health"
Write-Host ''
