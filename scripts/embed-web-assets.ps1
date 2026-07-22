[CmdletBinding()]
param(
    [switch]$SkipTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[embed-web-assets] $Message"
}

function Invoke-Npm {
    param(
        [Parameter(Mandatory = $true)][string]$NpmPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )

    $display = "npm.cmd $($Arguments -join ' ')"
    Write-Step "Run: $display"
    Push-Location -LiteralPath $WorkingDirectory
    try {
        & $NpmPath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE`: $display"
        }
    }
    finally {
        Pop-Location
    }
}

function Assert-SafeTarget {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $workspaceFullPath = [System.IO.Path]::GetFullPath($WorkspaceRoot)
    $webuiRoot = [System.IO.Path]::GetFullPath((Join-Path $workspaceFullPath 'server\internal\webui'))
    $expectedTarget = [System.IO.Path]::GetFullPath((Join-Path $webuiRoot 'dist'))
    $targetFullPath = [System.IO.Path]::GetFullPath($TargetPath)
    $webuiPrefix = $webuiRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar

    if (-not $targetFullPath.Equals($expectedTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clear unexpected target: $targetFullPath"
    }
    if (-not $targetFullPath.StartsWith($webuiPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Embedded dist target must stay inside $webuiRoot`: $targetFullPath"
    }

    if (Test-Path -LiteralPath $targetFullPath) {
        $targetInfo = Get-Item -LiteralPath $targetFullPath -Force
        if (-not $targetInfo.PSIsContainer) {
            throw "Embedded dist target is not a directory: $targetFullPath"
        }
        if (($targetInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Embedded dist target must not be a reparse point: $targetFullPath"
        }

        $resolvedTarget = (Resolve-Path -LiteralPath $targetFullPath).Path
        if (-not $resolvedTarget.Equals($expectedTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Resolved embedded dist target is unexpected: $resolvedTarget"
        }
    }

    return $targetFullPath
}

function Clear-EmbeddedDist {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $safeTarget = Assert-SafeTarget -WorkspaceRoot $WorkspaceRoot -TargetPath $TargetPath
    New-Item -ItemType Directory -Path $safeTarget -Force | Out-Null
    $safeTarget = Assert-SafeTarget -WorkspaceRoot $WorkspaceRoot -TargetPath $safeTarget
    $targetPrefix = $safeTarget.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar

    foreach ($item in Get-ChildItem -LiteralPath $safeTarget -Force) {
        $itemFullPath = [System.IO.Path]::GetFullPath($item.FullName)
        if (-not $itemFullPath.StartsWith($targetPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove item outside embedded dist: $itemFullPath"
        }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to remove reparse point from embedded dist: $itemFullPath"
        }

        Remove-Item -LiteralPath $itemFullPath -Recurse -Force
    }
}

$workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$webRoot = Join-Path $workspaceRoot 'apps\web'
$sourceDist = Join-Path $webRoot 'dist'
$targetDist = Join-Path $workspaceRoot 'server\internal\webui\dist'
$packageJson = Join-Path $webRoot 'package.json'

if (-not (Test-Path -LiteralPath $packageJson -PathType Leaf)) {
    throw "Web application was not found: $packageJson"
}

$npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $npmCommand) {
    throw "npm.cmd was not found. Install Node.js and add npm to PATH."
}

Write-Step "Workspace: $workspaceRoot"
Invoke-Npm -NpmPath $npmCommand.Source -Arguments @('install') -WorkingDirectory $webRoot
if ($SkipTest) {
    Write-Step 'Skip web tests'
}
else {
    Invoke-Npm -NpmPath $npmCommand.Source -Arguments @('test') -WorkingDirectory $webRoot
}
Invoke-Npm -NpmPath $npmCommand.Source -Arguments @('run', 'build') -WorkingDirectory $webRoot

$sourceIndex = Join-Path $sourceDist 'index.html'
if (-not (Test-Path -LiteralPath $sourceIndex -PathType Leaf)) {
    throw "Web build did not produce an index file: $sourceIndex"
}

Clear-EmbeddedDist -WorkspaceRoot $workspaceRoot -TargetPath $targetDist
Copy-Item -Path (Join-Path $sourceDist '*') -Destination $targetDist -Recurse -Force

$targetIndex = Join-Path $targetDist 'index.html'
if (-not (Test-Path -LiteralPath $targetIndex -PathType Leaf)) {
    throw "Web build did not produce an index file: $targetIndex"
}

Write-Step 'Embedded web assets are ready'
