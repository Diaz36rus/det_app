#Requires -Version 5.1
<#
.SYNOPSIS
  Builds a portable Release pack of Det App for USB transfer.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\pack_release.ps1
#>
[CmdletBinding()]
param(
  [switch]$SkipBuild,
  [switch]$SkipVcRedist
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) {
  Write-Host ""
  Write-Host "==> $msg" -ForegroundColor Cyan
}

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $ProjectRoot

$ReleaseDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
$DistRoot = Join-Path $ProjectRoot "dist"
$PackDir = Join-Path $DistRoot "DetApp-portable"
$AppDir = Join-Path $PackDir "app"
$CacheDir = Join-Path $ProjectRoot "tools\cache"
$VcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
$VcRedistCached = Join-Path $CacheDir "vc_redist.x64.exe"
$ReadmeSrc = Join-Path $PSScriptRoot "portable_readme.txt"
$GithubSrc = Join-Path $PSScriptRoot "GITHUB.txt"

$stamp = Get-Date -Format "yyyyMMdd-HHmm"
$ZipPath = Join-Path $DistRoot "DetApp-portable-$stamp.zip"

# --- 1. Build ---
if (-not $SkipBuild) {
  Write-Step "flutter build windows --release"
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) {
    throw "flutter build windows --release failed (exit $LASTEXITCODE)"
  }
} else {
  Write-Step "Skip build (-SkipBuild)"
}

if (-not (Test-Path $ReleaseDir)) {
  throw "Release folder missing: $ReleaseDir. Run: flutter build windows --release"
}

# --- 2. Verify required files ---
Write-Step "Verify required files"
$requiredFiles = @(
  "det_app.exe",
  "flutter_windows.dll",
  "sqlite3.dll",
  "data\icudtl.dat",
  "data\app.so"
)
$missing = @()
foreach ($rel in $requiredFiles) {
  $full = Join-Path $ReleaseDir $rel
  if (-not (Test-Path $full)) {
    $missing += $rel
  }
}
$assetsDir = Join-Path $ReleaseDir "data\flutter_assets"
if (-not (Test-Path $assetsDir)) {
  $missing += "data\flutter_assets\"
}

if ($missing.Count -gt 0) {
  Write-Host "Missing files in Release:" -ForegroundColor Red
  $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  throw "Release bundle incomplete. Aborting pack."
}

$debugDlls = Get-ChildItem $ReleaseDir -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match '^(vcruntime\d+d|msvcp\d+d|ucrtbased)\.dll$' }
if ($debugDlls) {
  $names = ($debugDlls | ForEach-Object { $_.Name }) -join ', '
  throw "Debug CRT DLLs found in Release ($names). Not a portable Release."
}

Write-Host "OK: det_app.exe, flutter_windows.dll, sqlite3.dll, data\*" -ForegroundColor Green

# --- 3. Copy app (if dist locked by running app, still pack update zip from Release) ---
Write-Step "Copy to dist/DetApp-portable/app"
$packDirReady = $true
if (Test-Path $PackDir) {
  try {
    Remove-Item $PackDir -Recurse -Force -ErrorAction Stop
  } catch {
    $packDirReady = $false
    Write-Host "WARN: dist\DetApp-portable is locked (close Det App, or launch from D:\DetApp)." -ForegroundColor Yellow
    Write-Host "      Update zip will be built from Release; publish still works." -ForegroundColor Yellow
  }
}

if ($packDirReady) {
  New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
  Copy-Item -Path (Join-Path $ReleaseDir "*") -Destination $AppDir -Recurse -Force

  # --- 4. VC++ redistributable ---
  if (-not $SkipVcRedist) {
    Write-Step "Visual C++ Redistributable x64"
    if (-not (Test-Path $CacheDir)) {
      New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    }
    if (-not (Test-Path $VcRedistCached) -or ((Get-Item $VcRedistCached).Length -lt 1MB)) {
      Write-Host "Downloading vc_redist.x64.exe ..."
      Invoke-WebRequest -Uri $VcRedistUrl -OutFile $VcRedistCached -UseBasicParsing
    } else {
      Write-Host "Using cache: $VcRedistCached"
    }
    Copy-Item $VcRedistCached -Destination (Join-Path $PackDir "vc_redist.x64.exe") -Force
    $vcSize = (Get-Item (Join-Path $PackDir "vc_redist.x64.exe")).Length
    if ($vcSize -lt 1MB) {
      throw ("vc_redist.x64.exe too small ({0} bytes) - download likely failed." -f $vcSize)
    }
  } else {
    Write-Step "Skip vc_redist (-SkipVcRedist)"
  }

  # --- 5. Updater + channel template ---
  Write-Step "Updater + update_channel"
  $UpdateDir = Join-Path $PackDir "update"
  New-Item -ItemType Directory -Path $UpdateDir -Force | Out-Null
  $UpdaterSrc = Join-Path $PSScriptRoot "DetAppUpdate.ps1"
  if (-not (Test-Path $UpdaterSrc)) { throw "Missing $UpdaterSrc" }
  Copy-Item $UpdaterSrc -Destination (Join-Path $UpdateDir "DetAppUpdate.ps1") -Force

  $ChannelExample = Join-Path $PSScriptRoot "update_channel.example.json"
  if (Test-Path $ChannelExample) {
    Copy-Item $ChannelExample -Destination (Join-Path $PackDir "update_channel.example.json") -Force
    # Рабочий файл — правите URL домашнего сервера на студийных ПК
    Copy-Item $ChannelExample -Destination (Join-Path $PackDir "update_channel.json") -Force
  }

  # --- 6. README ---
  Write-Step "README"
  if (-not (Test-Path $ReadmeSrc)) {
    throw "Missing $ReadmeSrc"
  }
  $readmeBody = Get-Content -Path $ReadmeSrc -Raw -Encoding UTF8
  $readmeBody = $readmeBody.TrimEnd() + "`r`n`r`nPack stamp: $stamp`r`n"
  $readmeDest = Join-Path $PackDir "README.txt"
  [System.IO.File]::WriteAllText($readmeDest, $readmeBody, [System.Text.UTF8Encoding]::new($true))
  # Also Russian filename copy for convenience
  $readmeRu = Join-Path $PackDir "PROCHTI_MENYA.txt"
  Copy-Item $readmeDest $readmeRu -Force

  if (Test-Path $GithubSrc) {
    Copy-Item $GithubSrc -Destination (Join-Path $PackDir "GITHUB.txt") -Force
  } else {
    Write-Host "Warn: GITHUB.txt missing at $GithubSrc" -ForegroundColor Yellow
  }

  $SyncSrc = Join-Path $PSScriptRoot "SYNC_SETUP.txt"
  if (Test-Path $SyncSrc) {
    Copy-Item $SyncSrc -Destination (Join-Path $PackDir "SYNC_SETUP.txt") -Force
  } else {
    Write-Host "Warn: SYNC_SETUP.txt missing" -ForegroundColor Yellow
  }

  $UpdateSetupSrc = Join-Path $PSScriptRoot "UPDATE_SETUP.txt"
  if (Test-Path $UpdateSetupSrc) {
    Copy-Item $UpdateSetupSrc -Destination (Join-Path $PackDir "UPDATE_SETUP.txt") -Force
  }
} else {
  # App-update zip from fresh Release when staging is locked
  $AppDir = $ReleaseDir
}

# --- 7. Version from pubspec ---
Write-Step "Read version from pubspec.yaml"
$pubspec = Get-Content (Join-Path $ProjectRoot "pubspec.yaml") -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9.]+)\+(\d+)') {
  throw "Cannot parse version from pubspec.yaml"
}
$appVersion = $Matches[1]
$appBuild = [int]$Matches[2]
# db_schema must match lib/app_version.dart
$dbSchema = 20
if ($pubspec -match 'dbSchema\s*=\s*(\d+)') { $dbSchema = [int]$Matches[1] }
# Prefer reading from app_version.dart
$appVerDart = Join-Path $ProjectRoot "lib\app_version.dart"
if (Test-Path $appVerDart) {
  $av = Get-Content $appVerDart -Raw
  if ($av -match 'dbSchema\s*=\s*(\d+)') { $dbSchema = [int]$Matches[1] }
}
Write-Host "version=$appVersion build=$appBuild dbSchema=$dbSchema"

# --- 8. App-only zip for auto-update ---
Write-Step "Create app-update zip"
if (-not (Test-Path $DistRoot)) {
  New-Item -ItemType Directory -Path $DistRoot -Force | Out-Null
}
$AppZipName = "DetApp-app-$appVersion+$appBuild.zip"
$AppZipPath = Join-Path $DistRoot $AppZipName
if (Test-Path $AppZipPath) { Remove-Item $AppZipPath -Force }

# Compress-Archive не умеет «содержимое папки» без обёртки — копируем во временную и зипуем содержимое через .NET
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $AppZipPath) { Remove-Item $AppZipPath -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($AppDir, $AppZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

$sha = (Get-FileHash -LiteralPath $AppZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$zipSize = (Get-Item $AppZipPath).Length

$latest = [ordered]@{
  version      = $appVersion
  build        = $appBuild
  min_build    = 1
  url          = "REPLACE_WITH_PUBLISH_URL/packs/$AppZipName"
  sha256       = $sha
  size         = $zipSize
  released_at  = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
  notes        = "Сборка $stamp"
  db_version   = $dbSchema
  critical     = $false
}

# Android APK (if release apk already built) for LAN phone updates
$ApkSrc = Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-release.apk"
# Без «+» в имени: в URL/браузере «+» часто превращается в пробел и ломает скачивание.
$ApkName = "DetApp-${appVersion}-b${appBuild}-android.apk"
$ApkDist = Join-Path $DistRoot $ApkName
$apkSha = $null
$apkSize = $null
if (Test-Path $ApkSrc) {
  Write-Step "Include Android APK in latest.json"
  Copy-Item $ApkSrc -Destination $ApkDist -Force
  $apkSha = (Get-FileHash -LiteralPath $ApkDist -Algorithm SHA256).Hash.ToLowerInvariant()
  $apkSize = (Get-Item $ApkDist).Length
  $latest['android_url'] = "REPLACE_WITH_PUBLISH_URL/packs/$ApkName"
  $latest['android_sha256'] = $apkSha
  $latest['android_size'] = $apkSize
  $apkMb = [math]::Round($apkSize / 1MB, 1)
  Write-Host ("APK: {0} ({1} MB)" -f $ApkName, $apkMb) -ForegroundColor Green

  # Ручная установка на телефон — на D: рядом с проектом (не Desktop / не C:).
  $ApkDropDir = Join-Path $ProjectRoot 'apk'
  New-Item -ItemType Directory -Path $ApkDropDir -Force | Out-Null
  Copy-Item $ApkDist -Destination (Join-Path $ApkDropDir $ApkName) -Force
  Copy-Item $ApkDist -Destination (Join-Path $ApkDropDir 'DetApp-latest-android.apk') -Force
  Write-Host ("APK drop:  {0}" -f $ApkDropDir) -ForegroundColor Green
} else {
  Write-Host "No app-release.apk - skip android fields. Run: flutter build apk --release" -ForegroundColor Yellow
}

$latestPath = Join-Path $DistRoot 'latest.json'
[System.IO.File]::WriteAllText(
  $latestPath,
  (($latest | ConvertTo-Json -Depth 5) + "`r`n"),
  [System.Text.UTF8Encoding]::new($false)
)

$meta = [ordered]@{
  zip_name   = $AppZipName
  version    = $appVersion
  build      = $appBuild
  sha256     = $sha
  db_version = $dbSchema
}
if ($apkSha) {
  $meta['apk_name'] = $ApkName
  $meta['android_sha256'] = $apkSha
  $meta['android_size'] = $apkSize
}
[System.IO.File]::WriteAllText(
  (Join-Path $DistRoot 'update_pack_meta.json'),
  (($meta | ConvertTo-Json) + "`r`n"),
  [System.Text.UTF8Encoding]::new($false)
)

# --- 9. Full portable zip ---
if ($packDirReady) {
  Write-Step "Create portable zip"
  if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
  }
  Compress-Archive -Path $PackDir -DestinationPath $ZipPath -Force
  $zipSizeMb = [math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
} else {
  Write-Step "Skip portable zip (staging folder locked)"
  $ZipPath = $null
  $zipSizeMb = $null
}

$appZipMb = [math]::Round((Get-Item $AppZipPath).Length / 1MB, 1)
Write-Host ""
Write-Host "Done." -ForegroundColor Green
if ($packDirReady) {
  Write-Host "Folder:     $PackDir"
  Write-Host "Portable:   $ZipPath  ($zipSizeMb MB)"
} else {
  Write-Host "Folder:     (skipped - use D:\DetApp for daily launch)"
}
Write-Host ("App update: {0} ({1} MB)" -f $AppZipPath, $appZipMb)
Write-Host "Manifest:   $latestPath"
Write-Host "SHA256:     $sha"
if ($apkSha) {
  Write-Host ("Phone APK:  {0}\DetApp-latest-android.apk" -f (Join-Path $ProjectRoot 'apk'))
}
Write-Host ""
Write-Host "Publish to home server:" -ForegroundColor Yellow
Write-Host "  powershell -ExecutionPolicy Bypass -File tools\publish_update.ps1 -PublishDir D:\detapp-updates -BaseUrl http://192.168.3.2:8080"
Write-Host ""
Write-Host "Daily launch: D:\DetApp\app\det_app.exe (not dist\)." -ForegroundColor Yellow
