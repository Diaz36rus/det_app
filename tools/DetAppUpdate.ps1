#Requires -Version 5.1
<#
.SYNOPSIS
  Replaces DetApp-portable\app with a new build after the main process exits.

.PARAMETER AppDir
  Current application folder (…\DetApp-portable\app)

.PARAMETER NewAppDir
  Extracted new build folder (must contain det_app.exe)

.PARAMETER WaitPid
  PID of det_app.exe to wait for

.PARAMETER ExeName
  Executable to relaunch (default det_app.exe)
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$AppDir,
  [Parameter(Mandatory = $true)][string]$NewAppDir,
  [Parameter(Mandatory = $true)][int]$WaitPid,
  [string]$ExeName = 'det_app.exe'
)

$ErrorActionPreference = 'Stop'
$LogDir = Join-Path $env:TEMP 'detapp-update-logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$Log = Join-Path $LogDir ("update-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

function Write-Log([string]$msg) {
  $line = "{0:HH:mm:ss}  {1}" -f (Get-Date), $msg
  Add-Content -Path $Log -Value $line -Encoding UTF8
}

try {
  Write-Log "Wait PID=$WaitPid"
  Write-Log "AppDir=$AppDir"
  Write-Log "NewAppDir=$NewAppDir"

  $deadline = (Get-Date).AddSeconds(90)
  while ((Get-Date) -lt $deadline) {
    $proc = Get-Process -Id $WaitPid -ErrorAction SilentlyContinue
    if (-not $proc) { break }
    Start-Sleep -Milliseconds 250
  }
  # Если процесс ещё жив — гасим, иначе rename app/ залочен
  $still = Get-Process -Id $WaitPid -ErrorAction SilentlyContinue
  if ($still) {
    Write-Log "PID $WaitPid still alive — Stop-Process"
    Stop-Process -Id $WaitPid -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
  }
  Start-Sleep -Milliseconds 400

  if (-not (Test-Path (Join-Path $NewAppDir $ExeName))) {
    throw "New build missing $ExeName in $NewAppDir"
  }
  if (-not (Test-Path $AppDir)) {
    throw "AppDir not found: $AppDir"
  }

  $parent = Split-Path -Parent $AppDir
  $bak = Join-Path $parent 'app.bak'
  if (Test-Path $bak) {
    Write-Log "Remove old app.bak"
    Remove-Item -LiteralPath $bak -Recurse -Force
  }

  Write-Log "Rename app -> app.bak"
  $renamed = $false
  for ($i = 0; $i -lt 15; $i++) {
    try {
      Rename-Item -LiteralPath $AppDir -NewName 'app.bak' -ErrorAction Stop
      $renamed = $true
      break
    } catch {
      Write-Log "Rename retry $($i+1): $($_.Exception.Message)"
      Start-Sleep -Milliseconds 400
    }
  }
  if (-not $renamed) { throw "Cannot rename app -> app.bak (file locked?)" }

  Write-Log "Copy new app"
  New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
  Copy-Item -Path (Join-Path $NewAppDir '*') -Destination $AppDir -Recurse -Force

  $exe = Join-Path $AppDir $ExeName
  if (-not (Test-Path $exe)) {
    throw "Copy failed, missing $exe — restoring bak"
  }

  Write-Log "Start $exe"
  Start-Process -FilePath $exe -WorkingDirectory $AppDir

  # Cleanup bak after successful launch (keep on failure)
  Start-Sleep -Seconds 2
  $alive = Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($ExeName)) -ErrorAction SilentlyContinue
  if ($alive) {
    Write-Log "App running — remove app.bak"
    Remove-Item -LiteralPath $bak -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    Write-Log "App not detected — keep app.bak for manual restore"
  }

  Write-Log "Done"
  exit 0
}
catch {
  Write-Log "ERROR: $($_.Exception.Message)"
  # Restore backup if we moved app away and new app is broken
  $parent = Split-Path -Parent $AppDir
  $bak = Join-Path $parent 'app.bak'
  if ((Test-Path $bak) -and -not (Test-Path (Join-Path $AppDir $ExeName))) {
    Write-Log "Restore app.bak -> app"
    if (Test-Path $AppDir) { Remove-Item -LiteralPath $AppDir -Recurse -Force -ErrorAction SilentlyContinue }
    Rename-Item -LiteralPath $bak -NewName 'app' -ErrorAction SilentlyContinue
    $restoredDir = Join-Path $parent 'app'
    $restoredExe = Join-Path $restoredDir $ExeName
    if (Test-Path $restoredExe) {
      Start-Process -FilePath $restoredExe -WorkingDirectory $restoredDir
    }
  }
  exit 1
}
