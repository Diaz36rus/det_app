# Create release keystore for RuStore / cloud APK.
# Run from repo root:
#   powershell -ExecutionPolicy Bypass -File tools\create_release_keystore.ps1
# Do not share the password in chat. Backup: upload-keystore.jks + key.properties.

param(
  [string]$Alias = 'upload',
  [string]$DName = 'CN=Det App, OU=DetApp, O=DetApp, L=Moscow, C=RU',
  [int]$ValidityDays = 10000
)

$ErrorActionPreference = 'Stop'
$androidDir = Join-Path $PSScriptRoot '..\android' | Resolve-Path
$jks = Join-Path $androidDir 'upload-keystore.jks'
$props = Join-Path $androidDir 'key.properties'

if (Test-Path $jks) {
  Write-Host "Already exists: $jks"
  Write-Host "To recreate, move/rename the old file and run again."
  exit 0
}

$keytool = $null
$candidates = @(
  (Get-Command keytool -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
  "$env:JAVA_HOME\bin\keytool.exe",
  "$env:LOCALAPPDATA\Programs\Android Studio\jbr\bin\keytool.exe",
  "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe"
)
foreach ($c in $candidates) {
  if ($c -and (Test-Path $c)) { $keytool = $c; break }
}
if (-not $keytool) { throw 'keytool not found. Install JDK or Android Studio.' }

$passSecure = Read-Host 'Keystore password (save it somewhere safe)' -AsSecureString
$passConfirm = Read-Host 'Repeat password' -AsSecureString
$bstr1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($passSecure)
$bstr2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($passConfirm)
try {
  $pass = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr1)
  $pass2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr2)
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)
}
if ($pass -ne $pass2) { throw 'Passwords do not match.' }
if ($pass.Length -lt 6) { throw 'Password too short (min 6).' }

& $keytool -genkeypair -v `
  -keystore $jks `
  -storetype JKS `
  -keyalg RSA `
  -keysize 2048 `
  -validity $ValidityDays `
  -alias $Alias `
  -storepass $pass `
  -keypass $pass `
  -dname $DName
if ($LASTEXITCODE -ne 0) { throw "keytool failed: $LASTEXITCODE" }

@(
  "storePassword=$pass"
  "keyPassword=$pass"
  "keyAlias=$Alias"
  "storeFile=upload-keystore.jks"
) | Set-Content -Path $props -Encoding ASCII

Write-Host ""
Write-Host "OK: $jks"
Write-Host "OK: $props  (gitignored)"
Write-Host "Backup the .jks and password. Lost key = cannot update the RuStore app."
