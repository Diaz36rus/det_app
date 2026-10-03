#Requires -Version 5.1
<#
.SYNOPSIS
  Сборка AAB и выгрузка версии в RuStore (черновик + карточка + модерация).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\ship_store.ps1 -DryRun
  powershell -ExecutionPolicy Bypass -File tools\ship_store.ps1
  powershell -ExecutionPolicy Bypass -File tools\ship_store.ps1 -Status
  powershell -ExecutionPolicy Bypass -File tools\ship_store.ps1 -Watch
  powershell -ExecutionPolicy Bypass -File tools\ship_store.ps1 -Resume
  powershell -ExecutionPolicy Bypass -File tools\ship_store.ps1 -Fresh
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$Status,
  [switch]$Watch,
  [switch]$Resume,
  [switch]$Fresh,
  [switch]$Manual,
  [int]$Priority = 0,
  [int]$Interval = 90
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $ProjectRoot

$py = $null
foreach ($c in @('python', 'py')) {
  $cmd = Get-Command $c -ErrorAction SilentlyContinue
  if ($cmd) { $py = $cmd.Source; break }
}
if (-not $py) { throw 'python not found in PATH' }

$script = Join-Path $PSScriptRoot 'publish_rustore.py'
if (-not (Test-Path -LiteralPath $script)) { throw "missing $script" }

function Invoke-RuStore {
  param([string[]]$PyArgs)
  & $py $script @PyArgs
  if ($LASTEXITCODE -ne 0) { throw "publish_rustore.py failed: $LASTEXITCODE" }
}

if ($Status) {
  Invoke-RuStore -PyArgs @('--status')
  return
}
if ($Watch -and -not $Resume -and -not $Fresh -and -not $DryRun) {
  # Watch alone: poll current version, do not build.
  $wargs = @('--watch', '--interval', "$Interval")
  Invoke-RuStore -PyArgs $wargs
  return
}
if ($DryRun) {
  Invoke-RuStore -PyArgs @('--dry-run')
  return
}

Write-Host '==> flutter build appbundle --release' -ForegroundColor Cyan
flutter build appbundle --release
if ($LASTEXITCODE -ne 0) { throw 'appbundle build failed' }

$aab = Join-Path $ProjectRoot 'build\app\outputs\bundle\release\app-release.aab'
if (-not (Test-Path -LiteralPath $aab)) { throw "missing AAB $aab" }

$pyArgs = @('--aab', $aab, '--priority', "$Priority")
if ($Resume) { $pyArgs += '--resume' }
if ($Fresh) { $pyArgs += '--fresh' }
if ($Manual) { $pyArgs += '--manual' }
if ($Watch) { $pyArgs += @('--watch', '--interval', "$Interval") }

Write-Host '==> publish_rustore.py' -ForegroundColor Cyan
Invoke-RuStore -PyArgs $pyArgs
