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
$files = @(
  @{ Local = 'models.py'; Remote = 'models.py' },
  @{ Local = 'main.py'; Remote = 'main.py' },
  @{ Local = 'schemas.py'; Remote = 'schemas.py' },
  @{ Local = 'seed.py'; Remote = 'seed.py' },
  @{ Local = 'config.py'; Remote = 'config.py' },
  @{ Local = 'crm_extra_schemas.py'; Remote = 'crm_extra_schemas.py' },
  @{ Local = 'price_catalog.py'; Remote = 'price_catalog.py' },
  @{ Local = 'lead_util.py'; Remote = 'lead_util.py' },
  @{ Local = 'telegram_notify.py'; Remote = 'telegram_notify.py' },
  @{ Local = 'webhooks.py'; Remote = 'webhooks.py' },
  @{ Local = 'studio_wipe.py'; Remote = 'studio_wipe.py' },
  @{ Local = 'rate_limit.py'; Remote = 'rate_limit.py' },
  @{ Local = 'security.py'; Remote = 'security.py' },
  @{ Local = 'deps.py'; Remote = 'deps.py' },
  @{ Local = 'routers\auth.py'; Remote = 'routers/auth.py' },
  @{ Local = 'routers\bugs.py'; Remote = 'routers/bugs.py' },
  @{ Local = 'routers\company.py'; Remote = 'routers/company.py' },
  @{ Local = 'routers\site.py'; Remote = 'routers/site.py' },
  @{ Local = 'routers\updates.py'; Remote = 'routers/updates.py' },
  @{ Local = 'routers\crm.py'; Remote = 'routers/crm.py' },
  @{ Local = 'routers\crm_extra.py'; Remote = 'routers/crm_extra.py' },
  @{ Local = 'routers\public.py'; Remote = 'routers/public.py' },
  @{ Local = 'routers\webhooks.py'; Remote = 'routers/webhooks.py' },
  @{ Local = 'routers\telegram_bot.py'; Remote = 'routers/telegram_bot.py' }
)
foreach ($f in $files) {
  $src = Join-Path $apiLocal $f.Local
  if (-not (Test-Path $src)) { throw "missing: $src" }
  Write-Host ("  scp {0}" -f $f.Local)
  & $scp @sshArgs $src "${remote}:/opt/det-app/api/app/$($f.Remote)"
  if ($LASTEXITCODE -ne 0) { throw "scp $($f.Local) failed" }
}

Write-Host '==> upload infra (Dockerfile, requirements, compose, Caddyfile, backup)' -ForegroundColor Cyan
$serverLocal = Join-Path $root 'server'
& $ssh @sshArgs $remote 'mkdir -p /opt/det-app/backup'
$infra = @(
  @{ Local = 'api\Dockerfile'; Remote = 'api/Dockerfile' },
  @{ Local = 'api\requirements.txt'; Remote = 'api/requirements.txt' },
  @{ Local = 'docker-compose.yml'; Remote = 'docker-compose.yml' },
  @{ Local = 'Caddyfile'; Remote = 'Caddyfile' },
  @{ Local = 'backup\backup.sh'; Remote = 'backup/backup.sh' },
  @{ Local = 'backup\loop.sh'; Remote = 'backup/loop.sh' }
)
foreach ($f in $infra) {
  $src = Join-Path $serverLocal $f.Local
  if (-not (Test-Path $src)) { throw "missing: $src" }
  Write-Host ("  scp {0}" -f $f.Local)
  & $scp @sshArgs $src "${remote}:/opt/det-app/$($f.Remote)"
  if ($LASTEXITCODE -ne 0) { throw "scp $($f.Local) failed" }
}
& $ssh @sshArgs $remote "sed -i 's/\r$//' /opt/det-app/backup/*.sh && chmod 600 /opt/det-app/.env"

Write-Host '==> rebuild api + reload caddy + start db-backup' -ForegroundColor Cyan
& $ssh @sshArgs $remote 'cd /opt/det-app && docker compose build api && docker compose run --rm --no-deps --user root --entrypoint chown api -R 10001:10001 /data/releases && docker compose up -d api && docker compose up -d db-backup && docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile && sleep 10 && curl -sf https://api.det-app.ru/health'
Write-Host ''
if ($LASTEXITCODE -ne 0) { throw 'api rebuild failed' }

Write-Host '==> verify crm_cars.year' -ForegroundColor Cyan
$verifyLocal = Join-Path $PSScriptRoot '_verify_year_remote.sh'
@'
#!/bin/bash
set -e
cd /opt/det-app
docker compose exec -T db psql -U detapp -d detapp -tAc "SELECT column_name FROM information_schema.columns WHERE table_name = 'crm_cars' AND column_name = 'year'"
'@ | Set-Content -Path $verifyLocal -Encoding ascii
& $scp @sshArgs $verifyLocal "${remote}:/tmp/det_verify_year.sh"
& $ssh @sshArgs $remote "sed -i 's/\r$//' /tmp/det_verify_year.sh && bash /tmp/det_verify_year.sh"
if ($LASTEXITCODE -ne 0) { throw 'year column check failed' }
Remove-Item -Force $verifyLocal -ErrorAction SilentlyContinue
Write-Host 'Done.' -ForegroundColor Green
