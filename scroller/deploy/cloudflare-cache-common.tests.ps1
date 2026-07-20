# Lightweight assertions for cloudflare-cache-common.ps1 (no Pester required).
# Run: powershell -File scroller/deploy/cloudflare-cache-common.tests.ps1

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\cloudflare-cache-common.ps1"

$failed = 0
function Assert-Equal {
    param($Expected, $Actual, [string]$Name)
    if ("$Expected" -ne "$Actual") {
        Write-Host "FAIL: $Name`n  expected: $Expected`n  actual:   $Actual"
        $script:failed++
    } else {
        Write-Host "OK: $Name"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Name)
    Assert-Equal $true $Condition $Name
}

$hosts = @(Get-BscrollerCacheHosts -ApexHost 'bscroller.navedu.uk')
Assert-equal 'bscroller.navedu.uk' $hosts[0] 'includes apex host when apex given'
Assert-equal 'www.bscroller.navedu.uk' $hosts[1] 'includes www host when apex given'

$fromWww = @(Get-BscrollerCacheHosts -ApexHost 'www.bscroller.navedu.uk')
Assert-equal 'bscroller.navedu.uk' $fromWww[0] 'normalizes www apex to bare host'
Assert-equal 'www.bscroller.navedu.uk' $fromWww[1] 'keeps www companion after normalize'

$expr = New-BscrollerPathCacheExpression -Hosts $hosts -PathPrefixes @('/canvaskit/')
Assert-equal `
    '(http.host in {"bscroller.navedu.uk" "www.bscroller.navedu.uk"} and starts_with(http.request.uri.path, "/canvaskit/"))' `
    $expr `
    'builds canvaskit expression for apex and www'

$staticExpr = New-BscrollerPathCacheExpression -Hosts $hosts -PathPrefixes @('/assets/', '/icons/')
Assert-equal `
    '(http.host in {"bscroller.navedu.uk" "www.bscroller.navedu.uk"} and (starts_with(http.request.uri.path, "/assets/") or starts_with(http.request.uri.path, "/icons/")))' `
    $staticExpr `
    'builds assets/icons expression with or-joined paths'

$rule = [pscustomobject]@{
    id          = 'abc123'
    description = 'other rule'
    expression  = '(true)'
    action      = 'set_cache_settings'
    enabled     = $true
    ref         = 'sibling-ref'
    logging     = @{ enabled = $true }
    last_updated = '2026-01-01T00:00:00Z'
    version     = '2'
    action_parameters = @{ cache = $true }
}
$writable = ConvertTo-WritableCacheRule $rule
Assert-equal 'abc123' $writable.id 'keeps id on writable rule'
Assert-equal 'sibling-ref' $writable.ref 'preserves ref on writable rule'
Assert-equal $true $writable.logging.enabled 'preserves logging.enabled on writable rule'
Assert-equal $false ($writable.Keys -contains 'last_updated') 'strips last_updated from writable rule'
Assert-equal $false ($writable.Keys -contains 'version') 'strips version from writable rule'

$nullRules = @(Normalize-CfRulesetRules $null)
Assert-equal 0 $nullRules.Count 'returns empty array when rules is null'

$missingRules = @(Normalize-CfRulesetRules @())
Assert-equal 0 $missingRules.Count 'returns empty array when rules is empty'

$one = [pscustomobject]@{ description = 'keep-me'; expression = '(true)'; action = 'set_cache_settings'; enabled = $true }
$normalizedOne = @(Normalize-CfRulesetRules @($one))
Assert-equal 1 $normalizedOne.Count 'preserves single existing rule'
Assert-equal 'keep-me' $normalizedOne[0].description 'preserves rule description when normalizing'

$singlePrefixJson = ConvertTo-CfApiJsonBody @{ prefixes = @('bscroller.navedu.uk/canvaskit') }
Assert-True ($singlePrefixJson -match '"prefixes"\s*:\s*\[') 'serializes single prefixes value as JSON array'
Assert-True ($singlePrefixJson -notmatch '"prefixes"\s*:\s*"bscroller') 'does not collapse prefixes to a bare string'

$singleRuleJson = ConvertTo-CfApiJsonBody @{
    rules = @(
        @{
            expression = '(true)'
            action     = 'set_cache_settings'
            enabled    = $true
        }
    )
}
Assert-True ($singleRuleJson -match '"rules"\s*:\s*\[') 'serializes single rules value as JSON array'

# PS 5.1 often unwraps a one-element rules array to a bare hashtable.
$unwrappedRuleJson = ConvertTo-CfApiJsonBody @{
    rules = @{
        expression = '(true)'
        action     = 'set_cache_settings'
        enabled    = $true
    }
}
Assert-True ($unwrappedRuleJson -match '"rules"\s*:\s*\[') 'serializes unwrapped single hashtable rules value as JSON array'
Assert-True ($unwrappedRuleJson -notmatch '"rules"\s*:\s*\{') 'does not serialize unwrapped rules as a bare object'

$err = [System.Management.Automation.ErrorRecord]::new(
    (New-Object System.Exception 'The remote server returned an error: (404) Not Found.'),
    'NotFound',
    [System.Management.Automation.ErrorCategory]::InvalidOperation,
    $null
)
Assert-equal 404 (Get-CfHttpStatusCode $err) 'parses 404 from exception message when Response is null'

$errDetails = [System.Management.Automation.ErrorRecord]::new(
    (New-Object System.Exception 'request failed'),
    'NotFound',
    [System.Management.Automation.ErrorCategory]::InvalidOperation,
    $null
)
$errDetails.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('{"success":false,"errors":[{"code":10000,"message":"not found"}]} (404)')
Assert-equal 404 (Get-CfHttpStatusCode $errDetails) 'parses 404 from ErrorDetails when Response is null'

if ($failed -gt 0) {
    Write-Host "FAILED: $failed assertion(s)"
    exit 1
}
Write-Host 'All common helper assertions passed.'
exit 0
