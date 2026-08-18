#Requires -Version 5.1
<#
.SYNOPSIS
  Block A: Det App regression (isolated DB) + API smoke.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\run_regression.ps1
#>
$ErrorActionPreference = 'Stop'
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $ProjectRoot

Write-Host "==> flutter test test/full_regression_test.dart" -ForegroundColor Cyan
flutter test test/full_regression_test.dart
if ($LASTEXITCODE -ne 0) {
  Write-Host "FAIL: regression red - do not ship." -ForegroundColor Red
  exit $LASTEXITCODE
}

Write-Host ""
Write-Host "==> flutter test test/api_smoke_test.dart (needs network)" -ForegroundColor Cyan
flutter test test/api_smoke_test.dart
if ($LASTEXITCODE -ne 0) {
  Write-Host "FAIL: API smoke - check api.det-app.ru / network." -ForegroundColor Red
  exit $LASTEXITCODE
}

Write-Host ""
Write-Host "OK: Block A automated tests green." -ForegroundColor Green
Write-Host "Next (manual): tools\HOME_SMOKE.txt"
