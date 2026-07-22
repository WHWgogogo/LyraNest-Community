[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '..'),
    [string]$ArtifactRoot = '',
    [string]$OutputRoot = '',
    [string]$BuildStamp = (Get-Date -Format 'yyyyMMdd-HHmmss'),
    [ValidateSet('release-signed', 'test-signed')]
    [string]$AndroidSigningMode = 'test-signed',
    [switch]$AndroidOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[package-delivery] $Message"
}

function Resolve-ExistingDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ErrorMessage
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw $ErrorMessage
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-ExistingFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ErrorMessage
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw $ErrorMessage
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

try {
    $repoRoot = Resolve-ExistingDirectory -Path $RepositoryRoot -ErrorMessage "Repository directory does not exist: $RepositoryRoot"

    if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) {
        $ArtifactRoot = $repoRoot
    }
    $artifactRootPath = Resolve-ExistingDirectory -Path $ArtifactRoot -ErrorMessage "Artifact root directory does not exist: $ArtifactRoot"

    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        $OutputRoot = Join-Path $repoRoot 'dist\delivery'
    }
    $deliveryRoot = Get-FullPath -Path $OutputRoot
    New-Item -ItemType Directory -Path $deliveryRoot -Force | Out-Null
    $deliveryRoot = (Resolve-Path -LiteralPath $deliveryRoot).Path

    $apkSource = Resolve-ExistingFile `
        -Path (Join-Path $artifactRootPath 'apps\player\build\app\outputs\flutter-apk\app-release.apk') `
        -ErrorMessage "Android Release APK was not found. Run: flutter build apk --release --target-platform=android-arm64"

    $apkDeliveryPath = Join-Path $deliveryRoot "player-android-$AndroidSigningMode-$BuildStamp.apk"
    $sha256Path = Join-Path $deliveryRoot 'SHA256SUMS.txt'

    $windowsZipPath = $null
    if (-not $AndroidOnly) {
        $windowsReleaseDir = Resolve-ExistingDirectory `
            -Path (Join-Path $artifactRootPath 'apps\player\build\windows\x64\runner\Release') `
            -ErrorMessage "Windows Release directory was not found. Run: flutter build windows --release"

        $windowsZipPath = Join-Path $deliveryRoot "player-windows-release-$BuildStamp.zip"
        Write-Step "Compress Windows Release directory: $windowsReleaseDir"
        Compress-Archive -LiteralPath $windowsReleaseDir -DestinationPath $windowsZipPath -CompressionLevel Optimal -Force
    }

    Write-Step "Copy Android APK ($AndroidSigningMode): $apkSource"
    Copy-Item -LiteralPath $apkSource -Destination $apkDeliveryPath -Force

    $artifactPaths = @()
    if ($null -ne $windowsZipPath) {
        $artifactPaths += (Resolve-Path -LiteralPath $windowsZipPath).Path
    }
    $artifactPaths += (Resolve-Path -LiteralPath $apkDeliveryPath).Path

    $artifactRecords = foreach ($artifactPath in $artifactPaths) {
        $artifact = Get-Item -LiteralPath $artifactPath
        $hash = Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256
        [pscustomobject]@{
            Path = $artifact.FullName
            Length = $artifact.Length
            Sha256 = $hash.Hash.ToLowerInvariant()
        }
    }

    $hashLines = $artifactRecords | ForEach-Object {
        "{0}  {1}" -f $_.Sha256, (Split-Path -Leaf $_.Path)
    }

    Set-Content -LiteralPath $sha256Path -Value $hashLines -Encoding ASCII
    $sha256Path = (Resolve-Path -LiteralPath $sha256Path).Path

    $windowsRecord = $null
    if (-not $AndroidOnly) {
        $windowsRecord = $artifactRecords | Where-Object { $_.Path -eq (Resolve-Path -LiteralPath $windowsZipPath).Path } | Select-Object -First 1
    }
    $androidRecord = $artifactRecords | Where-Object { $_.Path -eq (Resolve-Path -LiteralPath $apkDeliveryPath).Path } | Select-Object -First 1
    $windowsZip = $null
    $windowsZipLength = $null
    $windowsZipSha256 = $null
    if ($null -ne $windowsRecord) {
        $windowsZip = $windowsRecord.Path
        $windowsZipLength = $windowsRecord.Length
        $windowsZipSha256 = $windowsRecord.Sha256
    }

    Write-Step "Delivery directory: $deliveryRoot"
    if ($null -ne $windowsRecord) {
        Write-Host "Windows ZIP: $($windowsRecord.Path) ($($windowsRecord.Length) bytes, SHA256 $($windowsRecord.Sha256))"
    }
    Write-Host "Android APK: $($androidRecord.Path) ($($androidRecord.Length) bytes, SHA256 $($androidRecord.Sha256))"
    Write-Host "SHA256SUMS: $sha256Path"

    [pscustomobject]@{
        DeliveryDirectory = $deliveryRoot
        WindowsZip = $windowsZip
        WindowsZipLength = $windowsZipLength
        WindowsZipSha256 = $windowsZipSha256
        AndroidApk = $androidRecord.Path
        AndroidApkLength = $androidRecord.Length
        AndroidApkSha256 = $androidRecord.Sha256
        Sha256Sums = $sha256Path
    }
}
catch {
    $message = "Delivery packaging failed: $($_.Exception.Message)"
    Write-Error $message -ErrorAction Continue
    throw $message
}
