Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$deployScript = Join-Path $repoRoot 'scripts\deploy-remote.ps1'
$verifyScript = Join-Path $repoRoot 'scripts\verify-deployment.ps1'

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

foreach ($scriptPath in @($deployScript, $verifyScript)) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    Assert-True -Condition ($parseErrors.Count -eq 0) -Message ("PowerShell parser errors in {0}: {1}" -f $scriptPath, (($parseErrors | ForEach-Object { $_.Message }) -join '; '))
}

$deploySource = Get-Content -LiteralPath $deployScript -Raw -Encoding UTF8
Assert-True -Condition ($deploySource -match 'wait_for_service_health\(\)') -Message 'Deploy regression: missing health wait loop.'
Assert-True -Condition ($deploySource -match 'docker_health') -Message 'Deploy regression: Docker health status is not polled.'
Assert-True -Condition ($deploySource -match '/healthz') -Message 'Deploy regression: HTTP health endpoint is not polled.'
Assert-True -Condition ($deploySource -match 'collect_deployment_diagnostics') -Message 'Deploy regression: failure diagnostics are not collected.'
Assert-True -Condition ($deploySource -match 'Deployment diagnostics saved to') -Message 'Deploy regression: diagnostics are not persisted.'

$verifySource = Get-Content -LiteralPath $verifyScript -Raw -Encoding UTF8
Assert-True -Condition ($verifySource -match '\[System\.Security\.SecureString\]\$AuthToken') -Message 'Verify regression: SecureString token input is missing.'
Assert-True -Condition ($verifySource -match 'PromptForAuthToken') -Message 'Verify regression: secure token prompt is missing.'
Assert-True -Condition ($verifySource -match 'HARMONY_VERIFY_AUTH_TOKEN') -Message 'Verify regression: token environment variable support is missing.'
Assert-True -Condition ($verifySource -match 'Authenticated API checks skipped because no token was provided') -Message 'Verify regression: no-token API checks are not skipped.'
Assert-True -Condition ($verifySource -match '\[object\]\$SkipLibraryScan = \$true') -Message 'Verify regression: destructive library scan is not disabled by default.'

Write-Host 'Deployment reliability regression checks: OK'
