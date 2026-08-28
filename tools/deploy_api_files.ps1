#Requires -Version 5.1
<#
.SYNOPSIS
  Деплой только API-кода на Cali (без git pull) + rebuild api container.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\deploy_api_files.ps1
#>
[CmdletBinding()]
param(
  [string]$HostName = '135.106.186.90',
  [string]$User = 'root',
  [string]$KeyPath = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $KeyPath) { $KeyPath = Join-Path $env:USERPROFILE '.ssh\id_ed25519' }

$ssh = @('C:\Program Files\Git\usr\bin\ssh.exe','C:\Windows\System32\OpenSSH\ssh.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
$scp = @('C:\Program Files\Git\usr\bin\scp.exe','C:\Windows\System32\OpenSSH\scp.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ssh -or -not $scp) { throw 'ssh/scp not found' }
if (-not (Test-Path $KeyPath)) { throw "SSH key missing: $KeyPath" }

$remote = "${User}@${HostName}"
$sshArgs = @('-i', $KeyPath, '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new')
$apiLocal = Join-Path $root 'server\api\app'

Write-Host '==> upload API app sources' -ForegroundColor Cyan
& $scp @sshArgs (Join-Path $apiLocal 'models.py') "${remote}:/opt/det-app/api/app/models.py"
if ($LASTEXITCODE -ne 0) { throw 'scp models failed' }
& $scp @sshArgs (Join-Path $apiLocal 'main.py') "${remote}:/opt/det-app/api/app/main.py"
if ($LASTEXITCODE -ne 0) { throw 'scp main failed' }
& $scp @sshArgs (Join-Path $apiLocal 'schemas.py') "${remote}:/opt/det-app/api/app/schemas.py"
if ($LASTEXITCODE -ne 0) { throw 'scp schemas failed' }
& $scp @sshArgs (Join-Path $apiLocal 'routers\company.py') "${remote}:/opt/det-app/api/app/routers/company.py"
if ($LASTEXITCODE -ne 0) { throw 'scp company router failed' }
& $scp @sshArgs (Join-Path $apiLocal 'routers\site.py') "${remote}:/opt/det-app/api/app/routers/site.py"
if ($LASTEXITCODE -ne 0) { throw 'scp site router failed' }

Write-Host '==> rebuild api' -ForegroundColor Cyan
& $ssh @sshArgs $remote 'cd /opt/det-app && docker compose up -d --build api && sleep 4 && curl -s http://127.0.0.1/health'
Write-Host ''
if ($LASTEXITCODE -ne 0) { throw 'api rebuild failed' }
Write-Host 'Done.' -ForegroundColor Green
