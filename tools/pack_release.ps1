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

# --- 3. Copy app ---
Write-Step "Copy to dist/DetApp-portable/app"
if (Test-Path $PackDir) {
  Remove-Item $PackDir -Recurse -Force
}
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
    throw "vc_redist.x64.exe too small ($vcSize bytes) - download likely failed."
  }
} else {
  Write-Step "Skip vc_redist (-SkipVcRedist)"
}

# --- 5. README ---
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

# --- 6. Zip ---
Write-Step "Create zip"
if (-not (Test-Path $DistRoot)) {
  New-Item -ItemType Directory -Path $DistRoot -Force | Out-Null
}
if (Test-Path $ZipPath) {
  Remove-Item $ZipPath -Force
}
Compress-Archive -Path $PackDir -DestinationPath $ZipPath -Force

$zipSizeMb = [math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Folder: $PackDir"
Write-Host "Zip:    $ZipPath  ($zipSizeMb MB)"
Write-Host ""
Write-Host "Next: test in Windows Sandbox, then copy the zip to USB." -ForegroundColor Yellow
