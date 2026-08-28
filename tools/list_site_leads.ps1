#Requires -Version 5.1
<#
.SYNOPSIS
  Список заявок с сайта (POST /site/leads).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\list_site_leads.ps1 -Token DetAppRelease2026Token
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Token,
  [string]$ApiBase = 'http://api.det-app.ru'
)

$ErrorActionPreference = 'Stop'
$url = "$($ApiBase.TrimEnd('/'))/site/leads"
curl.exe -sS -H "X-Release-Token: $Token" $url
Write-Host ''
