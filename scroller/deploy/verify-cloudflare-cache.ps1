# Verifies Cloudflare edge-caching for bscroller Flutter shell assets.
# Exit 0 only when wasm reaches HIT (with retries) and main.dart.js is not year-long immutable.

$ErrorActionPreference = 'Stop'

$hostName = if ($env:BSCROLLER_HOST) { $env:BSCROLLER_HOST } else { 'bscroller.navedu.uk' }
if ($hostName.StartsWith('www.')) {
    $hostName = $hostName.Substring(4)
}
$wasmUrl = "https://$hostName/canvaskit/chromium/canvaskit.wasm"
$jsUrl = "https://$hostName/main.dart.js"
$maxAttempts = 5

function Get-ResponseHeaders([string]$Uri, [string]$Method = 'Head') {
    $response = Invoke-WebRequest -Uri $Uri -Method $Method -UseBasicParsing -TimeoutSec 120
    return $response.Headers
}

function Get-HeaderValue($headers, [string]$name) {
    foreach ($key in $headers.Keys) {
        if ($key -ieq $name) {
            $value = $headers[$key]
            if ($value -is [array]) { return ($value -join ', ') }
            return [string]$value
        }
    }
    return ''
}

Write-Host "Warming cache with GET $wasmUrl ..."
$warm = Get-ResponseHeaders $wasmUrl -Method Get
$warmStatus = Get-HeaderValue $warm 'CF-Cache-Status'
Write-Host "wasm warm(GET) CF-Cache-Status: $warmStatus"

$secondStatus = ''
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    Start-Sleep -Seconds 1
    $second = Get-ResponseHeaders $wasmUrl -Method Head
    $secondStatus = Get-HeaderValue $second 'CF-Cache-Status'
    Write-Host "wasm follow-up #$attempt CF-Cache-Status: $secondStatus"
    if ($secondStatus -ieq 'HIT') { break }
}

$js = Get-ResponseHeaders $jsUrl -Method Head
$jsStatus = Get-HeaderValue $js 'CF-Cache-Status'
$jsCache = Get-HeaderValue $js 'Cache-Control'
Write-Host "main.dart.js CF-Cache-Status: $jsStatus"
Write-Host "main.dart.js Cache-Control: $jsCache"

$failed = $false
if ($secondStatus -ine 'HIT') {
    Write-Host "FAIL: expected wasm CF-Cache-Status=HIT within $maxAttempts follow-ups, got '$secondStatus' (DYNAMIC means Cache Rule missing)."
    $failed = $true
} else {
    Write-Host 'OK: wasm is edge-cached (HIT).'
}

if ($jsCache -match 'max-age=31536000' -or $jsCache -match '\bimmutable\b') {
    Write-Host "FAIL: main.dart.js should stay short/no-cache for safe deploys; got '$jsCache'."
    $failed = $true
} else {
    Write-Host 'OK: main.dart.js is not year-long immutable.'
}

if ($failed) { exit 1 }
Write-Host 'All cache checks passed.'
exit 0
