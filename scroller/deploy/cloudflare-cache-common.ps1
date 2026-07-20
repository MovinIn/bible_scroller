# Shared helpers for bscroller Cloudflare cache scripts (dot-sourced).

function Get-BscrollerCacheHosts {
    param(
        [Parameter(Mandatory)][string]$ApexHost
    )
    $apex = $ApexHost.Trim().ToLowerInvariant()
    if ($apex.StartsWith('www.')) {
        $apex = $apex.Substring(4)
    }
    return @($apex, "www.$apex")
}

function New-BscrollerPathCacheExpression {
    param(
        [Parameter(Mandatory)][string[]]$Hosts,
        [Parameter(Mandatory)][string[]]$PathPrefixes
    )
    $hostList = ($Hosts | ForEach-Object { '"{0}"' -f $_ }) -join ' '
    $hostClause = "http.host in {$hostList}"
    $pathClauses = @(
        $PathPrefixes | ForEach-Object {
            'starts_with(http.request.uri.path, "{0}")' -f $_
        }
    )
    if ($pathClauses.Count -eq 1) {
        return "($hostClause and $($pathClauses[0]))"
    }
    $joined = ($pathClauses -join ' or ')
    return "($hostClause and ($joined))"
}

function ConvertTo-WritableCacheRule {
    param(
        [Parameter(Mandatory)]$Rule
    )
    $out = [ordered]@{
        expression = [string]$Rule.expression
        action     = [string]$Rule.action
        enabled    = [bool]$Rule.enabled
    }
    if ($Rule.PSObject.Properties.Name -contains 'id' -and $Rule.id) {
        $out.id = [string]$Rule.id
    }
    if ($Rule.PSObject.Properties.Name -contains 'description' -and $Rule.description) {
        $out.description = [string]$Rule.description
    }
    if ($Rule.PSObject.Properties.Name -contains 'action_parameters' -and $null -ne $Rule.action_parameters) {
        $out.action_parameters = $Rule.action_parameters
    }
    return $out
}

function Normalize-CfRulesetRules {
    param($Rules)
    if ($null -eq $Rules) {
        return @()
    }
    return @($Rules | Where-Object { $null -ne $_ })
}

function ConvertTo-CfPlainObject {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [string] -or $InputObject -is [bool] -or $InputObject -is [int] -or
        $InputObject -is [long] -or $InputObject -is [double] -or $InputObject -is [decimal]) {
        return $InputObject
    }
    if ($InputObject -is [hashtable] -or $InputObject -is [System.Collections.IDictionary]) {
        $dict = @{}
        foreach ($key in @($InputObject.Keys)) {
            $dict[[string]$key] = ConvertTo-CfPlainObject $InputObject[$key]
        }
        return $dict
    }
    if ($InputObject -is [System.Collections.IEnumerable]) {
        $items = New-Object System.Collections.ArrayList
        foreach ($item in $InputObject) {
            [void]$items.Add((ConvertTo-CfPlainObject $item))
        }
        return @($items.ToArray())
    }
    if ($null -ne $InputObject.PSObject -and $null -ne $InputObject.PSObject.Properties) {
        $dict = @{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $dict[$prop.Name] = ConvertTo-CfPlainObject $prop.Value
        }
        return $dict
    }
    return $InputObject
}

function ConvertTo-CfApiJsonBody {
    param(
        [Parameter(Mandatory)][hashtable]$Body,
        [string[]]$ArrayKeys = @('rules', 'prefixes', 'files', 'tags', 'hosts')
    )
    # PS 5.1 unwraps single-element arrays stored in hashtables to scalars.
    # Force known list keys back to ArrayList so JSON keeps [...] shape.
    $normalized = @{}
    foreach ($key in @($Body.Keys)) {
        $val = $Body[$key]
        if ($ArrayKeys -contains $key) {
            $items = New-Object System.Collections.Generic.List[object]
            if ($null -eq $val) {
                # empty list
            } elseif ($val -is [string]) {
                # Hashtable unwrap of @('only') becomes a scalar string in Windows PowerShell.
                $items.Add($val)
            } elseif ($val -is [hashtable] -or $val -is [System.Collections.IDictionary]) {
                # Hashtable unwrap of @(@{...}) becomes a single dictionary — do not enumerate keys.
                $items.Add((ConvertTo-CfPlainObject $val))
            } elseif ($val -is [System.Collections.IEnumerable]) {
                foreach ($item in $val) {
                    if ($null -ne $item) {
                        $items.Add((ConvertTo-CfPlainObject $item))
                    }
                }
            } else {
                $items.Add((ConvertTo-CfPlainObject $val))
            }
            $normalized[$key] = $items.ToArray()
        } else {
            $normalized[$key] = ConvertTo-CfPlainObject $val
        }
    }

    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = [int]::MaxValue
    return $serializer.Serialize($normalized)
}

function Get-CfHttpStatusCode {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    $response = $ErrorRecord.Exception.Response
    if ($null -ne $response) {
        if ($response -is [System.Net.Http.HttpResponseMessage]) {
            return [int]$response.StatusCode
        }
        return [int]$response.StatusCode
    }

    $text = ''
    if ($null -ne $ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $text = [string]$ErrorRecord.ErrorDetails.Message
    }
    if ([string]::IsNullOrWhiteSpace($text) -and $null -ne $ErrorRecord.Exception) {
        $text = [string]$ErrorRecord.Exception.Message
    }
    if ($text -match '\((\d{3})\)') {
        return [int]$Matches[1]
    }
    if ($text -match '(?i)\bstatus(?:\s*code)?\s*[:=]?\s*(\d{3})\b') {
        return [int]$Matches[1]
    }
    if ($text -match '(?i)\b(\d{3})\s+Not Found\b') {
        return [int]$Matches[1]
    }
    return $null
}

function New-CfApiHeaders {
    param([Parameter(Mandatory)][string]$Token)
    return @{
        Authorization  = "Bearer $Token"
        'Content-Type' = 'application/json'
    }
}

function Invoke-CfApi {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][hashtable]$Headers,
        [hashtable]$Body = $null
    )
    $params = @{
        Method          = $Method
        Uri             = $Uri
        Headers         = $Headers
        UseBasicParsing = $true
    }
    if ($null -ne $Body) {
        $params.Body = ConvertTo-CfApiJsonBody $Body
    }
    $response = Invoke-RestMethod @params
    if (-not $response.success) {
        throw "Cloudflare API failed: $($response.errors | ConvertTo-Json -Compress)"
    }
    return $response
}
