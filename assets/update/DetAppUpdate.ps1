#Requires -Version 5.1
<#
.SYNOPSIS
  Replaces DetApp\app with a new build after the main process exits.
  Always prefer running a TEMP copy of this script (app may be locked/replaced).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$AppDir,
  [Parameter(Mandatory = $true)][string]$NewAppDir,
  [Parameter(Mandatory = $true)][int]$WaitPid,
  [string]$ExeName = 'det_app.exe',
  [string]$ReadyFile = ''
)

$ErrorActionPreference = 'Stop'
$LogDir = Join-Path $env:TEMP 'detapp-update-logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$Log = Join-Path $LogDir ("update-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

function Write-Log([string]$msg) {
  $line = "{0:HH:mm:ss}  {1}" -f (Get-Date), $msg
  Add-Content -Path $Log -Value $line -Encoding UTF8
}

function Stop-DetAppProcesses {
  param([int]$PrimaryPid)
  $base = [IO.Path]::GetFileNameWithoutExtension($ExeName)
  if ($PrimaryPid -gt 0) {
    Stop-Process -Id $PrimaryPid -Force -ErrorAction SilentlyContinue
  }
  Get-Process -Name $base -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Log "Stop leftover PID=$($_.Id)"
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
  }
  Start-Sleep -Milliseconds 600
}

try {
  Write-Log "Updater start"
  Write-Log "Wait PID=$WaitPid"
  Write-Log "AppDir=$AppDir"
  Write-Log "NewAppDir=$NewAppDir"
  if ($ReadyFile) {
    Set-Content -LiteralPath $ReadyFile -Value 'started' -Encoding ASCII
  }

  $deadline = (Get-Date).AddSeconds(120)
  while ((Get-Date) -lt $deadline) {
    $proc = Get-Process -Id $WaitPid -ErrorAction SilentlyContinue
    if (-not $proc) { break }
    Start-Sleep -Milliseconds 250
  }

  Write-Log "Stop all $ExeName processes"
  Stop-DetAppProcesses -PrimaryPid $WaitPid

  if (-not (Test-Path -LiteralPath (Join-Path $NewAppDir $ExeName))) {
    throw "New build missing $ExeName in $NewAppDir"
  }
  if (-not (Test-Path -LiteralPath $AppDir)) {
    throw "AppDir not found: $AppDir"
  }

  $parent = Split-Path -Parent $AppDir
  $bak = Join-Path $parent 'app.bak'
  if (Test-Path -LiteralPath $bak) {
    Write-Log "Remove old app.bak"
    Remove-Item -LiteralPath $bak -Recurse -Force
  }

  Write-Log "Rename app -> app.bak"
  $renamed = $false
  for ($i = 0; $i -lt 25; $i++) {
    try {
      # Re-kill in case something respawned
      if ($i -eq 5 -or $i -eq 12) { Stop-DetAppProcesses -PrimaryPid 0 }
      Rename-Item -LiteralPath $AppDir -NewName 'app.bak' -ErrorAction Stop
      $renamed = $true
      break
    } catch {
      Write-Log "Rename retry $($i+1): $($_.Exception.Message)"
      Start-Sleep -Milliseconds 500
    }
  }
  if (-not $renamed) { throw "Cannot rename app -> app.bak (file locked?). Log: $Log" }

  Write-Log "Copy new app"
  New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
  Copy-Item -Path (Join-Path $NewAppDir '*') -Destination $AppDir -Recurse -Force

  $exe = Join-Path $AppDir $ExeName
  if (-not (Test-Path -LiteralPath $exe)) {
    throw "Copy failed, missing $exe — restoring bak"
  }

  # Refresh sibling updater script if present next to NewAppDir or in package root
  $siblingUpdate = Join-Path (Split-Path -Parent $NewAppDir) 'DetAppUpdate.ps1'
  $destUpdateDir = Join-Path $parent 'update'
  if (Test-Path -LiteralPath $siblingUpdate) {
    if (-not (Test-Path -LiteralPath $destUpdateDir)) {
      New-Item -ItemType Directory -Path $destUpdateDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $siblingUpdate -Destination (Join-Path $destUpdateDir 'DetAppUpdate.ps1') -Force
    Write-Log "Refreshed update\DetAppUpdate.ps1"
  }

  Write-Log "Start $exe"
  Start-Process -FilePath $exe -WorkingDirectory $AppDir

  Start-Sleep -Seconds 3
  $alive = Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($ExeName)) -ErrorAction SilentlyContinue
  if ($alive) {
    Write-Log "App running — remove app.bak"
    Remove-Item -LiteralPath $bak -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    Write-Log "App not detected — keep app.bak for manual restore"
  }

  if ($ReadyFile) {
    Set-Content -LiteralPath $ReadyFile -Value 'done' -Encoding ASCII
  }
  Write-Log "Done"
  exit 0
}
catch {
  Write-Log "ERROR: $($_.Exception.Message)"
  if ($ReadyFile) {
    Set-Content -LiteralPath $ReadyFile -Value ("error:" + $_.Exception.Message) -Encoding UTF8
  }
  $parent = Split-Path -Parent $AppDir
  $bak = Join-Path $parent 'app.bak'
  if ((Test-Path -LiteralPath $bak) -and -not (Test-Path -LiteralPath (Join-Path $AppDir $ExeName))) {
    Write-Log "Restore app.bak -> app"
    if (Test-Path -LiteralPath $AppDir) {
      Remove-Item -LiteralPath $AppDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Rename-Item -LiteralPath $bak -NewName 'app' -ErrorAction SilentlyContinue
    $restoredDir = Join-Path $parent 'app'
    $restoredExe = Join-Path $restoredDir $ExeName
    if (Test-Path -LiteralPath $restoredExe) {
      Start-Process -FilePath $restoredExe -WorkingDirectory $restoredDir
    }
  }
  exit 1
}
