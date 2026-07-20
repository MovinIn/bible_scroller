# Applies Cloudflare Cache Rules so Flutter CanvasKit (.wasm) is edge-cached.
# Requires: CLOUDFLARE_API_TOKEN with Zone.Cache Rules Edit (+ Zone.Settings Edit for browser TTL).
#
# Usage (from repo):
#   $env:CLOUDFLARE_API_TOKEN = '<token>'
#   powershell -File scroller/deploy/apply-cloudflare-cache-rules.ps1
#
# Optional:
#   $env:CLOUDFLARE_ZONE_NAME = 'navedu.uk'   # default
#   $env:BSCROLLER_HOST = 'bscroller.navedu.uk'  # default apex; www.<host> is always included
#   $env:CLOUDFLARE_SKIP_ZONE_BROWSER_TTL = '1'  # skip zone-wide browser_cache_ttl change

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\cloudflare-cache-common.ps1"

$token = $env:CLOUDFLARE_API_TOKEN
if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'Set CLOUDFLARE_API_TOKEN (Zone Cache Rules Edit + Zone Settings Edit).'
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
Write-Host "Zone id: $zoneId"
Write-Host ("Cache rule hosts: {0}" -f ($hosts -join ', '))

$skipZoneTtl = $env:CLOUDFLARE_SKIP_ZONE_BROWSER_TTL -eq '1'
if ($skipZoneTtl) {
    Write-Host 'Skipping zone browser_cache_ttl (CLOUDFLARE_SKIP_ZONE_BROWSER_TTL=1).'
} else {
    Write-Host 'WARNING: Setting browser_cache_ttl=0 applies to the ENTIRE zone (all hostnames on this zone), not only bscroller.'
    Write-Host 'Setting browser_cache_ttl to 0 (Respect Existing Headers) ...'
    Invoke-CfApi -Method PATCH -Uri "$api/zones/$zoneId/settings/browser_cache_ttl" -Headers $headers -Body @{ value = 0 } | Out-Null
}

$canvaskitExpr = New-BscrollerPathCacheExpression -Hosts $hosts -PathPrefixes @('/canvaskit/')
$staticExpr = New-BscrollerPathCacheExpression -Hosts $hosts -PathPrefixes @('/assets/', '/icons/')

$desiredRules = @(
    @{
        description = 'bscroller: edge-cache CanvasKit / wasm'
        expression  = $canvaskitExpr
        action      = 'set_cache_settings'
        enabled     = $true
        action_parameters = @{
            cache = $true
            edge_ttl = @{
                mode    = 'override_origin'
                default = 2678400  # 31 days
            }
        }
    },
    @{
        description = 'bscroller: edge-cache Flutter /assets and /icons'
        expression  = $staticExpr
        action      = 'set_cache_settings'
        enabled     = $true
        action_parameters = @{
            cache = $true
            edge_ttl = @{
                mode    = 'override_origin'
                default = 2678400
            }
        }
    }
)

Write-Host 'Reading http_request_cache_settings entrypoint ...'
$entrypointUri = "$api/zones/$zoneId/rulesets/phases/http_request_cache_settings/entrypoint"
$existingRules = @()
$rulesetId = $null
try {
    $existing = Invoke-CfApi -Method GET -Uri $entrypointUri -Headers $headers
    $existingRules = @(Normalize-CfRulesetRules $existing.result.rules)
    $rulesetId = $existing.result.id
} catch {
    $status = Get-CfHttpStatusCode $_
    if ($status -ne 404) {
        throw
    }
    Write-Host 'Entrypoint missing (404); creating zone ruleset ...'
    $created = Invoke-CfApi -Method POST -Uri "$api/zones/$zoneId/rulesets" -Headers $headers -Body @{
        name  = 'default'
        kind  = 'zone'
        phase = 'http_request_cache_settings'
        rules = @()
    }
    $existingRules = @()
    $rulesetId = $created.result.id
}

$kept = @(
    $existingRules |
        Where-Object { $_.description -notlike 'bscroller:*' } |
        ForEach-Object { ConvertTo-WritableCacheRule $_ }
)
$merged = @($kept) + @($desiredRules | ForEach-Object { ConvertTo-WritableCacheRule $_ })

Write-Host "Updating cache ruleset $rulesetId ($($merged.Count) rules) ..."
Invoke-CfApi -Method PUT -Uri "$api/zones/$zoneId/rulesets/$rulesetId" -Headers $headers -Body @{
    rules = $merged
} | Out-Null

Write-Host 'Done. After Flutter web deploys, purge edge cache:'
Write-Host "  powershell -File scroller/deploy/purge-cloudflare-flutter-static.ps1"
Write-Host 'Verify with:'
Write-Host "  powershell -File scroller/deploy/verify-cloudflare-cache.ps1"
