#Requires -Version 5.1
<#
.SYNOPSIS
  Пакует dist и выгружает Windows zip + Android APK на api.det-app.ru

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\publish_cloud.ps1 -Token "ВАШ_ТОКЕН"

  С пересборкой Windows:
  powershell -ExecutionPolicy Bypass -File tools\publish_cloud.ps1 -Token "ВАШ_ТОКЕН" -Build

  + Android APK:
  powershell -ExecutionPolicy Bypass -File tools\publish_cloud.ps1 -Token "ВАШ_ТОКЕН" -Build -BuildApk
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Token,
  [string]$ApiBase = 'http://api.det-app.ru',
  [switch]$Build,
  [switch]$BuildApk,
  [string]$Notes = ''
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $ProjectRoot

if ($Build) {
  Write-Host "==> flutter build windows --release" -ForegroundColor Cyan
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw "windows build failed" }
}
if ($BuildApk) {
  Write-Host "==> flutter build apk --release" -ForegroundColor Cyan
  flutter build apk --release
  if ($LASTEXITCODE -ne 0) { throw "apk build failed" }
}

Write-Host "==> pack_release.ps1 -SkipBuild" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'pack_release.ps1') -SkipBuild
if ($LASTEXITCODE -ne 0) { throw "pack_release failed" }

$DistRoot = Join-Path $ProjectRoot 'dist'
$PackMeta = Join-Path $DistRoot 'update_pack_meta.json'
if (-not (Test-Path $PackMeta)) { throw "missing $PackMeta" }
$meta = Get-Content $PackMeta -Raw -Encoding UTF8 | ConvertFrom-Json

$zipName = [string]$meta.zip_name
$ZipSrc = Join-Path $DistRoot $zipName
if (-not (Test-Path $ZipSrc)) { throw "missing zip $ZipSrc" }

# «Сборка» через codepoints — иначе PS 5.1 читает .ps1 не в UTF-8 и портит строку.
$sborka = -join ([char[]](0x0421, 0x0431, 0x043E, 0x0440, 0x043A, 0x0430))
$notesVal = if ($Notes) { $Notes } else { "$sborka $($meta.version)+$($meta.build)" }
$url = ($ApiBase.TrimEnd('/')) + '/updates/publish'

# curl -F "notes=..." из аргументов PS тоже ломает UTF-8 → пишем файл и шлём его.
$notesFile = Join-Path $env:TEMP ("detapp-release-notes-{0}.txt" -f [guid]::NewGuid().ToString('n'))
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($notesFile, $notesVal, $utf8NoBom)

$curlArgs = @(
  '-sS', '-X', 'POST',
  '-H', "X-Release-Token: $Token",
  '-F', "version=$($meta.version)",
  '-F', "build=$($meta.build)",
  '-F', 'min_build=1',
  '-F', "notes=<$notesFile;type=text/plain;charset=UTF-8",
  '-F', "db_version=$($meta.db_version)",
  '-F', 'critical=false',
  '-F', "sha256=$($meta.sha256)",
  '-F', "size=$((Get-Item -LiteralPath $ZipSrc).Length)",
  '-F', "windows_zip=@$ZipSrc;type=application/zip"
)

if ($meta.PSObject.Properties.Name -contains 'apk_name' -and $meta.apk_name) {
  $ApkSrc = Join-Path $DistRoot ([string]$meta.apk_name)
  if (-not (Test-Path -LiteralPath $ApkSrc)) { throw "missing apk $ApkSrc" }
  $curlArgs += @(
    '-F', "android_apk=@$ApkSrc;type=application/vnd.android.package-archive",
    '-F', "android_sha256=$($meta.android_sha256)",
    '-F', "android_size=$($meta.android_size)"
  )
}

$curlArgs += $url
Write-Host "==> POST $url" -ForegroundColor Cyan
try {
  & curl.exe @curlArgs
  if ($LASTEXITCODE -ne 0) { throw "upload failed (curl exit $LASTEXITCODE)" }
} finally {
  Remove-Item -LiteralPath $notesFile -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "OK. Канал для устройств:" -ForegroundColor Green
Write-Host "  $ApiBase/updates/latest.json"
