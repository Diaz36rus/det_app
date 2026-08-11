#Requires -Version 5.1
<#
.SYNOPSIS
  Copies Windows zip + Android APK + latest.json into a publish folder (LAN update server).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\publish_update.ps1 `
    -PublishDir C:\detapp-updates `
    -BaseUrl http://192.168.3.2:8080

  Then:
    cd C:\detapp-updates
    python -m http.server 8080
#>
[CmdletBinding()]
param(
  [string]$PublishDir = 'C:\detapp-updates',
  [Parameter(Mandatory = $true)][string]$BaseUrl,
  [string]$Notes = ''
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$DistRoot = Join-Path $ProjectRoot 'dist'
$ManifestSrc = Join-Path $DistRoot 'latest.json'
$PackMeta = Join-Path $DistRoot 'update_pack_meta.json'

if (-not (Test-Path $ManifestSrc) -or -not (Test-Path $PackMeta)) {
  throw "Run tools\pack_release.ps1 first (need dist\latest.json and update_pack_meta.json)."
}

$meta = Get-Content $PackMeta -Raw -Encoding UTF8 | ConvertFrom-Json
$zipName = [string]$meta.zip_name
$ZipSrc = Join-Path $DistRoot $zipName
if (-not (Test-Path $ZipSrc)) {
  throw "Missing zip: $ZipSrc"
}

$BaseUrl = $BaseUrl.TrimEnd('/')
$packsDir = Join-Path $PublishDir 'packs'
New-Item -ItemType Directory -Path $packsDir -Force | Out-Null

Copy-Item $ZipSrc -Destination (Join-Path $packsDir $zipName) -Force

$manifest = Get-Content $ManifestSrc -Raw -Encoding UTF8 | ConvertFrom-Json
$manifest.url = "$BaseUrl/packs/$zipName"
if ($Notes) { $manifest.notes = $Notes }

$apkName = $null
if ($meta.PSObject.Properties.Name -contains 'apk_name' -and $meta.apk_name) {
  $apkName = [string]$meta.apk_name
  $ApkSrc = Join-Path $DistRoot $apkName
  if (-not (Test-Path $ApkSrc)) {
    throw "Missing APK: $ApkSrc (rebuild: flutter build apk --release && pack_release)"
  }
  Copy-Item $ApkSrc -Destination (Join-Path $packsDir $apkName) -Force
  $manifest | Add-Member -NotePropertyName android_url -NotePropertyValue "$BaseUrl/packs/$apkName" -Force
  if ($meta.android_sha256) {
    $manifest | Add-Member -NotePropertyName android_sha256 -NotePropertyValue ([string]$meta.android_sha256) -Force
  }
  if ($meta.android_size) {
    $manifest | Add-Member -NotePropertyName android_size -NotePropertyValue ([int64]$meta.android_size) -Force
  }
}

$outManifest = Join-Path $PublishDir 'latest.json'
$json = $manifest | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($outManifest, $json + "`r`n", [System.Text.UTF8Encoding]::new($false))

$channelExample = Join-Path $PublishDir 'update_channel.json'
[System.IO.File]::WriteAllText(
  $channelExample,
  (@{ manifest_url = "$BaseUrl/latest.json" } | ConvertTo-Json),
  [System.Text.UTF8Encoding]::new($false)
)

Write-Host ""
Write-Host "Published." -ForegroundColor Green
Write-Host "  $outManifest"
Write-Host "  packs\$zipName"
if ($apkName) { Write-Host "  packs\$apkName" }
Write-Host ""
Write-Host "Serve with:" -ForegroundColor Yellow
Write-Host "  cd `"$PublishDir`""
Write-Host "  python -m http.server 8080"
Write-Host ""
Write-Host "Phone / PC channel URL:" -ForegroundColor Yellow
Write-Host "  $BaseUrl/latest.json"
