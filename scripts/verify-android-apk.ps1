[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,
    [string]$AndroidSdkRoot = '',
    [ValidateRange(1MB, 500MB)]
    [Int64]$MaxApkBytes = 150MB
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[verify-android-apk] $Message"
}

function Resolve-ExistingFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "APK was not found: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-AndroidSdkRoot {
    param([Parameter(Mandatory = $true)][string]$Candidate)

    $sdkCandidates = @(
        $Candidate,
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($sdkCandidate in $sdkCandidates) {
        if (Test-Path -LiteralPath (Join-Path $sdkCandidate 'build-tools') -PathType Container) {
            return (Resolve-Path -LiteralPath $sdkCandidate).Path
        }
    }

    throw 'Android SDK was not found. Pass -AndroidSdkRoot or set ANDROID_SDK_ROOT.'
}

function Get-BuildToolsExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$SdkRoot,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $buildToolsRoot = Join-Path $SdkRoot 'build-tools'
    $buildToolsVersion = Get-ChildItem -LiteralPath $buildToolsRoot -Directory |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1
    if ($null -eq $buildToolsVersion) {
        throw "No Android build-tools versions were found in: $buildToolsRoot"
    }

    $executable = @(
        "$Name.exe",
        "$Name.bat",
        $Name
    ) | ForEach-Object {
        Join-Path $buildToolsVersion.FullName $_
    } | Where-Object {
        Test-Path -LiteralPath $_ -PathType Leaf
    } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($executable)) {
        throw "Android build-tools executable was not found for '$Name' in: $($buildToolsVersion.FullName)"
    }

    return $executable
}

function Invoke-Tool {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    Write-Step "Run: $FilePath $($Arguments -join ' ')"
    $output = & $FilePath @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $FilePath $($Arguments -join ' ')`n$output"
    }

    return $output
}

function Assert-Arm64Only {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedApkPath,
        [Parameter(Mandatory = $true)][string]$Aapt2Path
    )

    $badging = Invoke-Tool -FilePath $Aapt2Path -Arguments @('dump', 'badging', $ResolvedApkPath)
    $nativeCodeLine = $badging -split "`r?`n" | Where-Object { $_ -like 'native-code:*' } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($nativeCodeLine)) {
        throw 'aapt2 did not report native-code ABI declarations.'
    }

    $declaredAbis = @([regex]::Matches($nativeCodeLine, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
    if ($declaredAbis.Count -ne 1 -or $declaredAbis[0] -ne 'arm64-v8a') {
        throw "APK must declare only arm64-v8a, but aapt2 reported: $nativeCodeLine"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ResolvedApkPath)
    try {
        $nativeLibraries = @($archive.Entries | Where-Object { $_.FullName -match '^lib/[^/]+/.+\.so$' })
        $nativeAbis = @(
            $nativeLibraries |
                ForEach-Object { ($_.FullName -split '/')[1] } |
                Sort-Object -Unique
        )
        if ($nativeAbis.Count -ne 1 -or $nativeAbis[0] -ne 'arm64-v8a') {
            throw "APK contains native libraries for unsupported ABI directories: $($nativeAbis -join ', ')"
        }

        $nativeLibraryPaths = @($nativeLibraries | ForEach-Object FullName)
        foreach ($requiredLibrary in @('lib/arm64-v8a/libapp.so', 'lib/arm64-v8a/libflutter.so')) {
            if ($requiredLibrary -notin $nativeLibraryPaths) {
                throw "APK is missing required ARM64 Flutter library: $requiredLibrary"
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

try {
    $resolvedApkPath = Resolve-ExistingFile -Path $ApkPath
    $apk = Get-Item -LiteralPath $resolvedApkPath
    if ($apk.Length -gt $MaxApkBytes) {
        throw "APK size gate failed: $($apk.Length) bytes exceeds $MaxApkBytes bytes."
    }

    $sdkRoot = Resolve-AndroidSdkRoot -Candidate $AndroidSdkRoot
    $aapt2 = Get-BuildToolsExecutable -SdkRoot $sdkRoot -Name 'aapt2'
    $apksigner = Get-BuildToolsExecutable -SdkRoot $sdkRoot -Name 'apksigner'
    $zipalign = Get-BuildToolsExecutable -SdkRoot $sdkRoot -Name 'zipalign'

    Write-Step "APK size gate passed: $($apk.Length) bytes (max $MaxApkBytes)"
    [void](Invoke-Tool -FilePath $zipalign -Arguments @('-c', '-v', '4', $resolvedApkPath))
    [void](Invoke-Tool -FilePath $apksigner -Arguments @('verify', '--verbose', '--print-certs', $resolvedApkPath))
    Assert-Arm64Only -ResolvedApkPath $resolvedApkPath -Aapt2Path $aapt2
    Write-Step 'APK verification passed: aligned, signed, and ARM64-only.'
}
catch {
    Write-Error "Android APK verification failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
