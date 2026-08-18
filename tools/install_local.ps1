#Requires -Version 5.1
<#
.SYNOPSIS
  Copies dist\DetApp-portable to D:\DetApp and points the Desktop shortcut there.
  Run the app only from D:\DetApp so pack_release can wipe dist\ freely.
#>
[CmdletBinding()]
param(
  [string]$InstallDir = 'D:\DetApp',
  [string]$ManifestUrl = 'http://api.det-app.ru/updates/latest.json'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Src = Join-Path $ProjectRoot 'dist\DetApp-portable'
$ExeRel = 'app\det_app.exe'

if (-not (Test-Path (Join-Path $Src $ExeRel))) {
  throw "Missing build: $Src\$ExeRel - run tools\pack_release.ps1 first"
}

$running = Get-Process -Name 'det_app' -ErrorAction SilentlyContinue
if ($running) {
  throw "Close Det App first, then re-run install_local.ps1"
}

Write-Host "==> Copy $Src -> $InstallDir" -ForegroundColor Cyan
if (Test-Path $InstallDir) {
  Remove-Item $InstallDir -Recurse -Force
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path (Join-Path $Src '*') -Destination $InstallDir -Recurse -Force

$channel = @{ manifest_url = $ManifestUrl } | ConvertTo-Json
[System.IO.File]::WriteAllText(
  (Join-Path $InstallDir 'update_channel.json'),
  ($channel + "`r`n"),
  [System.Text.UTF8Encoding]::new($false)
)

$exe = Join-Path $InstallDir $ExeRel
$desk = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desk 'Det App.lnk'
$w = New-Object -ComObject WScript.Shell
$lnk = $w.CreateShortcut($lnkPath)
$lnk.TargetPath = $exe
$lnk.WorkingDirectory = Split-Path $exe -Parent
$lnk.Description = 'Det App (D:\DetApp)'
$lnk.Save()

Write-Host "OK: $exe" -ForegroundColor Green
Write-Host "Shortcut: $lnkPath"
Write-Host "Channel: $ManifestUrl"
Write-Host "Use only this shortcut from now on."
