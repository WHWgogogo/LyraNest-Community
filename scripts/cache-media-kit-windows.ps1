[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$CacheRoot,

    [ValidateNotNullOrEmpty()]
    [string]$BaseUrl = 'https://github.com/media-kit/libmpv-win32-audio-build/releases/download/2023-09-24',

    [string]$SourceDirectory,

    [string]$Proxy,

    [ValidateRange(10, 600)]
    [int]$TimeoutSec = 120,

    [switch]$Offline
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$releaseTag = '2023-09-24'
$fileInfo = [pscustomobject]@{
    Name = 'mpv-dev-x86_64-20230924-git-652a1dd.7z'
    Length = 5392413
    MD5 = 'cd738e16e2a19626d7cfa48801524f8c'
    SHA256 = '583af5a291fc99ae2641794ede1955c368eb4c19dc05f4f0a9c7f9456edeb6a8'
}

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[cache-media-kit-windows] $Message"
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
        [Parameter(Mandatory = $true)]$ExpectedFile
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $artifact = Get-Item -LiteralPath $Path
    if ($artifact.Length -ne $ExpectedFile.Length) {
        return $false
    }

    $sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sha256 -ne $ExpectedFile.SHA256) {
        return $false
    }

    $md5 = (Get-FileHash -LiteralPath $Path -Algorithm MD5).Hash.ToLowerInvariant()
    return $md5 -eq $ExpectedFile.MD5
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
    $CacheRoot = Join-Path $repoRoot 'dist\build-cache\media-kit\windows-audio'
}

$resolvedCacheRoot = Resolve-FullPath -Path $CacheRoot
$releaseDirectory = Join-Path $resolvedCacheRoot $releaseTag
New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null

$sourceDirectories = New-Object System.Collections.Generic.List[object]
if (-not [string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $sourceDirectories.Add([pscustomobject]@{
        Path = Resolve-FullPath -Path $SourceDirectory
        CleanInvalid = $false
    })
}
$sourceDirectories.Add([pscustomobject]@{
    Path = $resolvedCacheRoot
    CleanInvalid = $true
})
$sourceDirectories.Add([pscustomobject]@{
    Path = Join-Path $repoRoot 'apps\player\build\windows\x64'
    CleanInvalid = $true
})

$baseUri = $null
if (-not $Offline) {
    if (-not [System.Uri]::TryCreate($BaseUrl, [System.UriKind]::Absolute, [ref]$baseUri)) {
        throw "BaseUrl is not a valid absolute URL: $BaseUrl"
    }
    if ($baseUri.Scheme -ne 'https') {
        throw "BaseUrl must use HTTPS: $BaseUrl"
    }
}

$destination = Join-Path $releaseDirectory $fileInfo.Name
Write-Step "Cache file: $destination"

if (Test-TrustedArtifact -Path $destination -ExpectedFile $fileInfo) {
    Write-Step "Verified cached artifact: $($fileInfo.Name)"
}
else {
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        Write-Step "Remove invalid cached artifact: $destination"
        Remove-Item -LiteralPath $destination -Force
    }

    $trustedSource = $null
    foreach ($source in $sourceDirectories) {
        $candidate = Join-Path $source.Path $fileInfo.Name
        if (Test-TrustedArtifact -Path $candidate -ExpectedFile $fileInfo) {
            $trustedSource = $candidate
            break
        }

        if ($source.CleanInvalid -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            Write-Step "Remove invalid generated artifact: $candidate"
            Remove-Item -LiteralPath $candidate -Force
        }
    }

    if ($null -ne $trustedSource) {
        $legacyCachePath = Join-Path $resolvedCacheRoot $fileInfo.Name
        if ($trustedSource.Equals($legacyCachePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            Move-Item -LiteralPath $trustedSource -Destination $destination -Force
            Write-Step "Migrated verified legacy cache: $trustedSource"
        }
        else {
            Copy-Item -LiteralPath $trustedSource -Destination $destination -Force
            Write-Step "Copied verified local artifact: $trustedSource"
        }
    }
    elseif ($Offline) {
        $checkedDirectories = $sourceDirectories | ForEach-Object { $_.Path }
        throw "No verified local copy was found for $($fileInfo.Name). Checked: $($checkedDirectories -join ', ')"
    }
    else {
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
            Headers = @{
                'User-Agent' = 'music-player-media-kit-cache'
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
            $request.Proxy = $Proxy
        }

        $previousSecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest @request
            if (-not (Test-TrustedArtifact -Path $temporaryPath -ExpectedFile $fileInfo)) {
                throw "Size, SHA256, or MD5 verification failed for $downloadUrl"
            }
            Move-Item -LiteralPath $temporaryPath -Destination $destination -Force
        }
        finally {
            [System.Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
            if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }
    }
}

if (-not (Test-TrustedArtifact -Path $destination -ExpectedFile $fileInfo)) {
    throw "Cached media_kit Windows audio artifact failed final verification: $destination"
}

Write-Step 'media_kit Windows audio artifact is cached and verified.'
Write-Host "$($fileInfo.SHA256)  $($fileInfo.Name)"
