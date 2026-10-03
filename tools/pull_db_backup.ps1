#Requires -Version 5.1
<#
.SYNOPSIS
  Скачивает свежий дамп Postgres с Cali на локальный диск (копия вне сервера).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\pull_db_backup.ps1
  powershell -ExecutionPolicy Bypass -File tools\pull_db_backup.ps1 -Fresh   # сначала снять новый дамп
#>
[CmdletBinding()]
param(
  [string]$HostName = '135.106.186.90',
  [string]$User = 'root',
  [string]$KeyPath = '',
  [string]$Dest = 'D:\Backups\det-app',
  [int]$Keep = 30,
  [switch]$Fresh
)

$ErrorActionPreference = 'Stop'
if (-not $KeyPath) { $KeyPath = Join-Path $env:USERPROFILE '.ssh\id_ed25519' }
$ssh = @('C:\Program Files\Git\usr\bin\ssh.exe','C:\Windows\System32\OpenSSH\ssh.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
$scp = @('C:\Program Files\Git\usr\bin\scp.exe','C:\Windows\System32\OpenSSH\scp.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ssh -or -not $scp) { throw 'ssh/scp not found' }

$remote = "${User}@${HostName}"
$sshArgs = @('-i', $KeyPath, '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new')
New-Item -ItemType Directory -Force -Path $Dest | Out-Null

if ($Fresh) {
  Write-Host '==> fresh dump' -ForegroundColor Cyan
  & $ssh @sshArgs $remote 'cd /opt/det-app && docker compose exec -T db-backup /backup.sh'
  if ($LASTEXITCODE -ne 0) { throw 'remote backup failed' }
}

$name = (& $ssh @sshArgs $remote "cd /opt/det-app && docker compose exec -T db-backup sh -c 'ls -1t /backups/detapp_*.sql.gz | head -1'").Trim()
if (-not $name) { throw 'На сервере нет дампов (db-backup запущен?)' }
$file = Split-Path $name -Leaf
Write-Host "==> $file" -ForegroundColor Cyan
& $ssh @sshArgs $remote "cd /opt/det-app && docker compose cp db-backup:$name /tmp/$file"
& $scp @sshArgs "${remote}:/tmp/$file" (Join-Path $Dest $file)
& $ssh @sshArgs $remote "rm -f /tmp/$file"

Get-ChildItem $Dest -Filter 'detapp_*.sql.gz' | Sort-Object LastWriteTime -Descending | Select-Object -Skip $Keep | Remove-Item -Force
$size = [math]::Round((Get-Item (Join-Path $Dest $file)).Length / 1MB, 2)
Write-Host "Done: $Dest\$file ($size MB)" -ForegroundColor Green
