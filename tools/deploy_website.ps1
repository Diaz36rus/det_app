#Requires -Version 5.1
<#
.SYNOPSIS
  Выкладывает лендинг det-app.ru на Cali (Caddy + /srv/website).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\deploy_website.ps1
#>
[CmdletBinding()]
param(
  [string]$HostName = '135.106.186.90',
  [string]$User = 'root',
  [string]$KeyPath = '',
  [string]$LocalWebsite = '',
  [string]$LocalCaddy = '',
  [string]$LocalCompose = '',
  [string]$InstallScript = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $KeyPath) { $KeyPath = Join-Path $env:USERPROFILE '.ssh\id_ed25519' }
if (-not $LocalWebsite) { $LocalWebsite = Join-Path $root 'server\website' }
if (-not $LocalCaddy) { $LocalCaddy = Join-Path $root 'server\Caddyfile' }
if (-not $LocalCompose) { $LocalCompose = Join-Path $root 'server\docker-compose.yml' }
if (-not $InstallScript) { $InstallScript = Join-Path $PSScriptRoot 'remote_install_website.sh' }

$sshCandidates = @(
  'C:\Program Files\Git\usr\bin\ssh.exe',
  'C:\Windows\System32\OpenSSH\ssh.exe'
)
$scpCandidates = @(
  'C:\Program Files\Git\usr\bin\scp.exe',
  'C:\Windows\System32\OpenSSH\scp.exe'
)
$ssh = $sshCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$scp = $scpCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ssh) { throw 'ssh.exe not found' }
if (-not $scp) { throw 'scp.exe not found' }
if (-not (Test-Path $KeyPath)) { throw "SSH key missing: $KeyPath" }
if (-not (Test-Path $LocalWebsite)) { throw "Website missing: $LocalWebsite" }
if (-not (Test-Path $InstallScript)) { throw "Install script missing: $InstallScript" }

$remote = "${User}@${HostName}"
$sshArgs = @('-i', $KeyPath, '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new')

# Ensure LF endings for remote bash
$lfScript = Join-Path $env:TEMP 'remote_install_website.sh'
$raw = [System.IO.File]::ReadAllText($InstallScript) -replace "`r`n", "`n" -replace "`r", "`n"
[System.IO.File]::WriteAllText($lfScript, $raw)

Write-Host '==> ensure remote dirs' -ForegroundColor Cyan
& $ssh @sshArgs $remote 'mkdir -p /opt/det-app/website /tmp'
if ($LASTEXITCODE -ne 0) { throw 'remote mkdir failed' }

Write-Host '==> upload website + install script' -ForegroundColor Cyan
& $scp @sshArgs -r $LocalWebsite "${remote}:/tmp/det-website-upload-src"
if ($LASTEXITCODE -ne 0) { throw 'scp website failed' }
& $scp @sshArgs $lfScript "${remote}:/tmp/remote_install_website.sh"
if ($LASTEXITCODE -ne 0) { throw 'scp install script failed' }

Write-Host '==> upload Caddyfile + compose' -ForegroundColor Cyan
& $scp @sshArgs $LocalCaddy "${remote}:/opt/det-app/Caddyfile"
if ($LASTEXITCODE -ne 0) { throw 'scp Caddyfile failed' }
& $scp @sshArgs $LocalCompose "${remote}:/opt/det-app/docker-compose.yml"
if ($LASTEXITCODE -ne 0) { throw 'scp compose failed' }

Write-Host '==> install + reload caddy' -ForegroundColor Cyan
& $ssh @sshArgs $remote 'bash /tmp/remote_install_website.sh'
if ($LASTEXITCODE -ne 0) { throw 'remote install failed' }

Write-Host '==> check site' -ForegroundColor Cyan
curl.exe -sI -H "Host: det-app.ru" "http://$HostName/" | Select-Object -First 8
Write-Host ''
curl.exe -sI "https://api.det-app.ru/health" | Select-Object -First 6
Write-Host ''
Write-Host 'Done. Open https://det-app.ru' -ForegroundColor Green
