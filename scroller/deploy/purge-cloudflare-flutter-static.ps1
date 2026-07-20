# Purges Cloudflare edge cache for bscroller Flutter static paths after a web deploy.
# Requires: CLOUDFLARE_API_TOKEN with Zone.Cache Purge.
#
# Usage:
#   $env:CLOUDFLARE_API_TOKEN = '<token>'
#   powershell -File scroller/deploy/purge-cloudflare-flutter-static.ps1

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\cloudflare-cache-common.ps1"

$token = $env:CLOUDFLARE_API_TOKEN
if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'Set CLOUDFLARE_API_TOKEN (Zone Cache Purge).'
}

$zoneName = if ($env:CLOUDFLARE_ZONE_NAME) { $env:CLOUDFLARE_ZONE_NAME } else { 'navedu.uk' }
$apexHost = if ($env:BSCROLLER_HOST) { $env:BSCROLLER_HOST } else { 'bscroller.navedu.uk' }
$hosts = @(Get-BscrollerCacheHosts -ApexHost $apexHost)
$api = 'https://api.cloudflare.com/client/v4'
$headers = New-CfApiHeaders -Token $token

Write-Host "Resolving zone $zoneName ..."
$zones = Invoke-CfApi -Method GET -Uri "$api/zones?name=$([uri]::EscapeDataString($zoneName))" -Headers $headers
if (-not $zones.result -or $zones.result.Count -lt 1) {
    throw "Zone not found: $zoneName"
}
$zoneId = $zones.result[0].id

$prefixes = foreach ($h in $hosts) {
    "$h/canvaskit"
    "$h/assets"
    "$h/icons"
}

Write-Host 'Purging prefixes:'
$prefixes | ForEach-Object { Write-Host "  $_" }

Invoke-CfApi -Method POST -Uri "$api/zones/$zoneId/purge_cache" -Headers $headers -Body @{
    prefixes = @($prefixes)
} | Out-Null

Write-Host 'Purge requested. Re-check with verify-cloudflare-cache.ps1 after a few seconds.'
