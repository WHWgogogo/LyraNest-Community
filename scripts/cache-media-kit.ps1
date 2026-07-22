[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$CacheRoot,

    [ValidateNotNullOrEmpty()]
    [string]$BaseUrl = 'https://github.com/media-kit/libmpv-android-audio-build/releases/download/v1.1.8',

    [string]$SourceDirectory,

    [string]$Proxy,

    [ValidateRange(10, 600)]
    [int]$TimeoutSec = 120,

    [switch]$Offline
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$version = 'v1.1.8'
$files = @(
    [pscustomobject]@{
        Name = 'default-arm64-v8a.jar'
        MD5 = '6f4af754ae94da8cbb24655fd66c07ed'
        SHA256 = '0481a64b5e246774da22573d7a4e67f9fb3d89a68630864d8819d3ff3a08bb09'
    },
    [pscustomobject]@{
        Name = 'default-armeabi-v7a.jar'
        MD5 = 'd8d1ba181d3d6ecb341e1e8d87506e17'
        SHA256 = '1bba852f5b7f0098c54ab8c3a945866d2b730b9e146b472a6ffaa80fc0dceae9'
    },
    [pscustomobject]@{
        Name = 'default-x86_64.jar'
        MD5 = '43ed7b0e6bdaa1a6ed2c1eee01f5e44a'
        SHA256 = 'ddffa0465e2dbb42d52937dae08516dbe07c534d489e9ea995f36a02d31a7106'
    },
    [pscustomobject]@{
        Name = 'default-x86.jar'
        MD5 = 'a2acb148c02d02f0892047f5c6c4f964'
        SHA256 = '824deeee316dfa3085832c6308e2953425bd428ba7eeeefd59bb51101b7ce8b7'
    }
)

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[cache-media-kit] $Message"
}

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

function Test-TrustedArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$FileInfo
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sha256 -ne $FileInfo.SHA256) {
        return $false
    }

    $md5 = (Get-FileHash -LiteralPath $Path -Algorithm MD5).Hash.ToLowerInvariant()
    return $md5 -eq $FileInfo.MD5
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
    $CacheRoot = Join-Path $repoRoot 'dist\build-cache\media-kit\android-audio'
}

$resolvedCacheRoot = Resolve-FullPath -Path $CacheRoot
$versionDirectory = Join-Path $resolvedCacheRoot $version
New-Item -ItemType Directory -Path $versionDirectory -Force | Out-Null

$sourceDirectories = New-Object System.Collections.Generic.List[string]
if (-not [string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $sourceDirectories.Add((Resolve-FullPath -Path $SourceDirectory))
}
$sourceDirectories.Add((Join-Path $repoRoot "apps\player\build\media_kit_libs_android_audio\$version"))
$sourceDirectories.Add((Join-Path $repoRoot 'apps\player\build\media_kit_libs_android_audio\output'))

$baseUri = $null
if (-not $Offline) {
    if (-not [System.Uri]::TryCreate($BaseUrl, [System.UriKind]::Absolute, [ref]$baseUri)) {
        throw "BaseUrl is not a valid absolute URL: $BaseUrl"
    }
    if ($baseUri.Scheme -ne 'https') {
        throw "BaseUrl must use HTTPS: $BaseUrl"
    }
}

Write-Step "Cache directory: $versionDirectory"

foreach ($fileInfo in $files) {
    $destination = Join-Path $versionDirectory $fileInfo.Name
    if (Test-TrustedArtifact -Path $destination -FileInfo $fileInfo) {
        Write-Step "Verified cached artifact: $($fileInfo.Name)"
        continue
    }

    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        Remove-Item -LiteralPath $destination -Force
    }

    $trustedSource = $null
    foreach ($directory in $sourceDirectories) {
        $candidate = Join-Path $directory $fileInfo.Name
        if (Test-TrustedArtifact -Path $candidate -FileInfo $fileInfo) {
            $trustedSource = $candidate
            break
        }
    }

    if ($null -ne $trustedSource) {
        Copy-Item -LiteralPath $trustedSource -Destination $destination
        Write-Step "Copied verified local artifact: $trustedSource"
        continue
    }

    if ($Offline) {
        throw "No verified local copy was found for $($fileInfo.Name). Checked: $($sourceDirectories -join ', ')"
    }

    $downloadUrl = "$($BaseUrl.TrimEnd('/'))/$($fileInfo.Name)"
    $temporaryPath = "$destination.download"
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }

    Write-Step "Downloading: $downloadUrl"
    $request = @{
        Uri = $downloadUrl
        OutFile = $temporaryPath
        TimeoutSec = $TimeoutSec
        UseBasicParsing = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
        $request.Proxy = $Proxy
    }

    try {
        Invoke-WebRequest @request
        if (-not (Test-TrustedArtifact -Path $temporaryPath -FileInfo $fileInfo)) {
            throw "SHA256 or MD5 verification failed for $downloadUrl"
        }
        Move-Item -LiteralPath $temporaryPath -Destination $destination -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

Write-Step 'All media_kit Android audio artifacts are cached and verified.'
$files | ForEach-Object {
    Write-Host "$($_.SHA256)  $($_.Name)"
}
