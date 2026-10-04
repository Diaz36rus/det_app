#Requires -Version 5.1
<#
.SYNOPSIS
  Поднимает GlitchTip (сбор ошибок) на Cali в /opt/glitchtip и перезагружает Caddy.
  Перед первым запуском: A-запись errors.det-app.ru -> 135.106.186.90.
  После запуска: зарегистрироваться на https://errors.det-app.ru (первый пользователь
  станет владельцем, дальше регистрация закрыта), создать проекты и взять DSN.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\deploy_glitchtip.ps1
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

Write-Host '==> upload compose + Caddyfile' -ForegroundColor Cyan
& $ssh @sshArgs $remote 'mkdir -p /opt/glitchtip'
& $scp @sshArgs (Join-Path $root 'server\glitchtip\compose.yml') "${remote}:/opt/glitchtip/compose.yml"
if ($LASTEXITCODE -ne 0) { throw 'scp compose.yml failed' }
& $scp @sshArgs (Join-Path $root 'server\Caddyfile') "${remote}:/opt/det-app/Caddyfile"
if ($LASTEXITCODE -ne 0) { throw 'scp Caddyfile failed' }

Write-Host '==> secrets (.env создаётся один раз) + start' -ForegroundColor Cyan
$remoteScript = @'
set -eu
cd /opt/glitchtip
sed -i 's/\r$//' compose.yml /opt/det-app/Caddyfile
if [ ! -f .env ]; then
  umask 077
  printf 'SECRET_KEY=%s\nPOSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 32)" "$(openssl rand -hex 24)" > .env
fi
chmod 600 .env
docker compose pull -q
docker compose up -d
cd /opt/det-app
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile
for i in $(seq 1 30); do
  if docker exec glitchtip-web python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8000/_health/')" 2>/dev/null; then
    echo "glitchtip healthy"; break
  fi
  sleep 5
done
docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' | grep -i glitchtip
'@
$tmp = Join-Path $env:TEMP 'det_glitchtip.sh'
$remoteScript | Set-Content -Path $tmp -Encoding ascii
& $scp @sshArgs $tmp "${remote}:/tmp/det_glitchtip.sh"
Remove-Item -Force $tmp -ErrorAction SilentlyContinue
& $ssh @sshArgs $remote "sed -i 's/\r$//' /tmp/det_glitchtip.sh && bash /tmp/det_glitchtip.sh; rc=`$?; rm -f /tmp/det_glitchtip.sh; exit `$rc"
if ($LASTEXITCODE -ne 0) { throw 'glitchtip start failed' }
Write-Host 'OK: https://errors.det-app.ru' -ForegroundColor Green
