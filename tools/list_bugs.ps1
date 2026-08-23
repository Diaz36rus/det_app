#Requires -Version 5.1
<#
.SYNOPSIS
  Список баг-репортов с api.det-app.ru (X-Release-Token или platform JWT).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\list_bugs.ps1 -Token DetAppRelease2026Token
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Token,
  [string]$ApiBase = 'http://api.det-app.ru',
  [ValidateSet('all', 'open', 'fixed')][string]$Status = 'open',
  [int]$Limit = 50
)

$ErrorActionPreference = 'Stop'
$url = ($ApiBase.TrimEnd('/')) + '/bugs?limit=' + $Limit
if ($Status -ne 'all') { $url += '&status=' + $Status }

$headers = @{ 'X-Release-Token' = $Token }
$json = curl.exe -sS -H "X-Release-Token: $Token" $url
if ($LASTEXITCODE -ne 0) { throw "curl failed" }
Write-Host $json
