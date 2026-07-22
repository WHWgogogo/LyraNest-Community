[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$DefaultServerUrl = 'http://192.168.0.107:8080',
    [switch]$AndroidOnly,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[build-clients] $Message"
}

function Resolve-AbsolutePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Resolve-Path -LiteralPath $Path).Path
}

function Test-ContainsNonAscii {
    param([Parameter(Mandatory = $true)][string]$Value)
    return ($Value -cmatch '[^\x00-\x7F]')
}

function Assert-Command {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$InstallHint
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        throw "Missing command '$Name'. $InstallHint"
    }

    return $command.Source
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )

    $display = "$FilePath $($Arguments -join ' ')"
    Write-Step "Run: $display"
    Push-Location -LiteralPath $WorkingDirectory
    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE`: $display"
        }
    }
    finally {
        Pop-Location
    }
}

function Assert-ServerUrl {
    param([Parameter(Mandatory = $true)][string]$Url)

    $uri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri)) {
        throw "DefaultServerUrl is not a valid absolute URL: $Url"
    }

    if ($uri.Scheme -notin @('http', 'https')) {
        throw "DefaultServerUrl must use http or https: $Url"
    }
}

function Assert-Flutter {
    $flutterPath = Assert-Command -Name 'flutter' -InstallHint 'Install Flutter SDK and add flutter to PATH.'
    Write-Step "Flutter detected: $flutterPath"
    & $flutterPath --version | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "flutter --version failed: $flutterPath"
    }

    return $flutterPath
}

function Get-JavaMajorVersion {
    param([Parameter(Mandatory = $true)][string]$VersionText)

    $match = [regex]::Match($VersionText, 'version "([^"]+)"')
    if (-not $match.Success) {
        $match = [regex]::Match($VersionText, 'openjdk ([0-9][^\s]*)')
    }

    if (-not $match.Success) {
        throw "Unable to parse Java version: $VersionText"
    }

    $version = $match.Groups[1].Value
    $parts = $version -split '[._-]'
    if ($parts[0] -eq '1' -and $parts.Count -gt 1) {
        return [int]$parts[1]
    }

    return [int]$parts[0]
}

function Invoke-JavaVersion {
    param([Parameter(Mandatory = $true)][string]$JavaPath)

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $JavaPath
    $startInfo.Arguments = '-version'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    try {
        if (-not $process.Start()) {
            throw "Failed to start java -version: $JavaPath"
        }

        $standardOutput = $process.StandardOutput.ReadToEnd()
        $standardError = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        $versionOutput = @(
            $standardOutput.Trim()
            $standardError.Trim()
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = ($versionOutput -join "`n")
        }
    }
    finally {
        $process.Dispose()
    }
}

function Assert-Jdk {
    $javaPath = $null

    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $candidate = Join-Path $env:JAVA_HOME 'bin\java.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $javaPath = $candidate
        }
    }

    if ([string]::IsNullOrWhiteSpace($javaPath)) {
        $javaPath = Assert-Command -Name 'java' -InstallHint 'Install JDK 17+ and configure JAVA_HOME or PATH.'
    }

    $versionResult = Invoke-JavaVersion -JavaPath $javaPath
    if ($versionResult.ExitCode -ne 0) {
        throw "java -version failed: $javaPath"
    }

    $majorVersion = Get-JavaMajorVersion -VersionText $versionResult.Output
    if ($majorVersion -lt 17) {
        throw "Detected Java $majorVersion, but Android/Gradle build requires JDK 17+."
    }

    Write-Step "JDK detected: $javaPath, version $majorVersion"
    return $javaPath
}

function Assert-AndroidSdk {
    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_SDK_ROOT)) {
        $candidates.Add($env:ANDROID_SDK_ROOT)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) {
        $candidates.Add($env:ANDROID_HOME)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Android\Sdk'))
    }

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate -PathType Container)) {
            continue
        }

        $platformsPath = Join-Path $candidate 'platforms'
        $buildToolsPath = Join-Path $candidate 'build-tools'
        $platformToolsPath = Join-Path $candidate 'platform-tools'

        $hasPlatforms = (Test-Path -LiteralPath $platformsPath -PathType Container) -and $null -ne (Get-ChildItem -LiteralPath $platformsPath -Directory -ErrorAction SilentlyContinue | Select-Object -First 1)
        $hasBuildTools = (Test-Path -LiteralPath $buildToolsPath -PathType Container) -and $null -ne (Get-ChildItem -LiteralPath $buildToolsPath -Directory -ErrorAction SilentlyContinue | Select-Object -First 1)
        $hasPlatformTools = Test-Path -LiteralPath $platformToolsPath -PathType Container

        if ($hasPlatforms -and $hasBuildTools -and $hasPlatformTools) {
            $resolvedSdk = Resolve-AbsolutePath -Path $candidate
            $env:ANDROID_SDK_ROOT = $resolvedSdk
            $env:ANDROID_HOME = $resolvedSdk
            Write-Step "Android SDK detected: $resolvedSdk"
            return $resolvedSdk
        }
    }

    throw "Complete Android SDK was not found. Set ANDROID_SDK_ROOT or ANDROID_HOME to a directory containing platforms, build-tools, and platform-tools."
}

function Assert-VisualStudio {
    $vsWhereCandidates = @()
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $vsWhereCandidates += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $vsWhereCandidates += (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
    }

    $vsWhere = $vsWhereCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($vsWhere)) {
        throw "vswhere.exe was not found. Install Visual Studio 2022 or Build Tools with Desktop development with C++."
    }

    $requireSets = @(
        @('Microsoft.VisualStudio.Workload.NativeDesktop'),
        @('Microsoft.VisualStudio.Component.VC.Tools.x86.x64')
    )

    foreach ($requires in $requireSets) {
        $arguments = @('-latest', '-products', '*', '-property', 'installationPath', '-requires') + $requires
        $installationPath = (& $vsWhere @arguments 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($installationPath)) {
            Write-Step "Visual Studio C++ toolchain detected: $installationPath"
            return $installationPath
        }
    }

    throw "Visual Studio C++ desktop toolchain was not found. Install Desktop development with C++ in Visual Studio 2022 or Build Tools."
}

function Get-AndroidReleaseSigningMode {
    $signingVariables = @(
        'HARMONY_ANDROID_KEYSTORE_PATH',
        'HARMONY_ANDROID_KEYSTORE_PASSWORD',
        'HARMONY_ANDROID_KEY_ALIAS',
        'HARMONY_ANDROID_KEY_PASSWORD'
    )
    $configuredVariables = @(
        $signingVariables | Where-Object { -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_)) }
    )

    if ($configuredVariables.Count -eq 0) {
        Write-Warning 'Android release APK will use the Android debug keystore for testing. Configure all HARMONY_ANDROID_KEYSTORE_* variables for a distributable signed release.'
        return 'test-signed'
    }

    if ($configuredVariables.Count -ne $signingVariables.Count) {
        throw "Incomplete Android release signing configuration. Set all of: $($signingVariables -join ', ')."
    }

    $keystorePath = [Environment]::GetEnvironmentVariable('HARMONY_ANDROID_KEYSTORE_PATH')
    if (-not (Test-Path -LiteralPath $keystorePath -PathType Leaf)) {
        throw "HARMONY_ANDROID_KEYSTORE_PATH does not point to a keystore file: $keystorePath"
    }

    Write-Step "Android release signing: external keystore $keystorePath"
    return 'release-signed'
}

function New-SubstMapping {
    param([Parameter(Mandatory = $true)][string]$TargetPath)

    $letters = @('Z', 'Y', 'X', 'W', 'V', 'U', 'T', 'S', 'R', 'Q', 'P')
    foreach ($letter in $letters) {
        $driveName = ('{0}:' -f $letter)
        $driveRoot = "$driveName\"
        $psDrive = Get-PSDrive -Name $letter -PSProvider FileSystem -ErrorAction SilentlyContinue
        if ($null -ne $psDrive -or (Test-Path -LiteralPath $driveRoot)) {
            continue
        }

        Write-Step "Map repository cache drive $driveName -> $TargetPath"
        & subst.exe $driveName $TargetPath
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create subst mapping: $driveName -> $TargetPath"
        }

        return [pscustomobject]@{
            DriveName = $driveName
            RootPath = $driveRoot.TrimEnd('\')
        }
    }

    throw "Non-ASCII repo path detected, but no free drive letter is available for subst."
}

function New-AsciiBuildWorkspace {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$WorkspaceBase
    )

    $workspaceBase = [System.IO.Path]::GetFullPath($WorkspaceBase).TrimEnd('\')
    if (Test-ContainsNonAscii -Value $workspaceBase) {
        throw "Build workspace root must use an ASCII path: $workspaceBase"
    }
    New-Item -ItemType Directory -Path $workspaceBase -Force | Out-Null

    $workspaceId = ([guid]::NewGuid().ToString('N')).Substring(0, 8)
    $workspaceRoot = Join-Path $workspaceBase "b-$workspaceId"
    $sourceClientRoot = Join-Path $RepositoryRoot 'apps\player'
    $targetClientRoot = Join-Path $workspaceRoot 'apps\player'
    New-Item -ItemType Directory -Path $targetClientRoot -Force | Out-Null

    $robocopyPath = Assert-Command -Name 'robocopy.exe' -InstallHint 'robocopy.exe is required to create the ASCII build workspace.'
    $robocopyArguments = @(
        $sourceClientRoot,
        $targetClientRoot,
        '/E',
        '/XJ',
        '/R:2',
        '/W:1',
        '/COPY:DAT',
        '/DCOPY:DAT',
        '/XD',
        'build',
        '.dart_tool',
        '.gradle',
        'ephemeral',
        '/XF',
        '.flutter-plugins-dependencies',
        'local.properties',
        '/NFL',
        '/NDL',
        '/NJH',
        '/NJS',
        '/NP'
    )

    Write-Step "Copy client sources to ASCII build workspace: $workspaceRoot"
    & $robocopyPath @robocopyArguments | Out-Host
    $robocopyExitCode = $LASTEXITCODE
    if ($robocopyExitCode -ge 8) {
        throw "Failed to copy client sources to ASCII build workspace. robocopy exit code: $robocopyExitCode"
    }

    $mediaCacheSource = Join-Path $RepositoryRoot 'dist\build-cache\media-kit\android-audio\v1.1.8'
    if (-not (Test-Path -LiteralPath $mediaCacheSource -PathType Container)) {
        throw "media_kit Android audio cache was not found: $mediaCacheSource"
    }

    $mediaCacheTarget = Join-Path $workspaceRoot 'dist\build-cache\media-kit\android-audio\v1.1.8'
    New-Item -ItemType Directory -Path $mediaCacheTarget -Force | Out-Null
    Get-ChildItem -LiteralPath $mediaCacheSource -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $mediaCacheTarget -Force
    }

    return [pscustomobject]@{
        RootPath = $workspaceRoot
        ClientRoot = $targetClientRoot
        WorkspaceBase = $workspaceBase
    }
}

function Remove-AsciiBuildWorkspace {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$WorkspaceBase
    )

    $workspacePath = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    $workspaceBase = [System.IO.Path]::GetFullPath($WorkspaceBase).TrimEnd('\')
    $expectedPrefix = "$workspaceBase\"
    $workspaceName = [System.IO.Path]::GetFileName($workspacePath)

    if (-not $workspacePath.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        $workspaceName -notmatch '^b-[0-9a-fA-F]{8}$') {
        throw "Refusing to remove unexpected build workspace: $workspacePath"
    }

    if (Test-Path -LiteralPath $workspacePath -PathType Container) {
        Get-ChildItem -LiteralPath $workspacePath -Recurse -Force -Attributes ReparsePoint | Sort-Object {
            $_.FullName.Length
        } -Descending | ForEach-Object {
            if ($_.PSIsContainer) {
                [System.IO.Directory]::Delete($_.FullName)
            }
            else {
                [System.IO.File]::Delete($_.FullName)
            }
        }

        Remove-Item -LiteralPath $workspacePath -Recurse -Force
    }
}

function Initialize-WindowsMediaKitArchive {
    param(
        [Parameter(Mandatory = $true)][string]$CacheRepositoryRoot,
        [Parameter(Mandatory = $true)][string]$BuildClientRoot
    )

    $archiveName = 'mpv-dev-x86_64-20230924-git-652a1dd.7z'
    $expectedMd5 = 'cd738e16e2a19626d7cfa48801524f8c'
    $expectedSha256 = '583af5a291fc99ae2641794ede1955c368eb4c19dc05f4f0a9c7f9456edeb6a8'
    $cachePath = Join-Path $CacheRepositoryRoot "dist\build-cache\media-kit\windows-audio\2023-09-24\$archiveName"

    $actualMd5 = (Get-FileHash -LiteralPath $cachePath -Algorithm MD5).Hash.ToLowerInvariant()
    $actualSha256 = (Get-FileHash -LiteralPath $cachePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualMd5 -ne $expectedMd5 -or $actualSha256 -ne $expectedSha256) {
        throw "Invalid media_kit Windows audio cache: $cachePath"
    }

    $buildArchiveDirectory = Join-Path $BuildClientRoot 'build\windows\x64'
    New-Item -ItemType Directory -Path $buildArchiveDirectory -Force | Out-Null
    $buildArchivePath = Join-Path $buildArchiveDirectory $archiveName
    if (Test-Path -LiteralPath $buildArchivePath -PathType Leaf) {
        Remove-Item -LiteralPath $buildArchivePath -Force
    }
    Copy-Item -LiteralPath $cachePath -Destination $buildArchivePath -Force

    $copiedSha256 = (Get-FileHash -LiteralPath $buildArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($copiedSha256 -ne $expectedSha256) {
        throw "Failed to seed verified media_kit Windows audio archive: $buildArchivePath"
    }

    Write-Step "Seed media_kit Windows audio archive from persistent cache"
}

$substMapping = $null
$buildWorkspace = $null
$previousGradleUserHome = $env:GRADLE_USER_HOME
$previousAndroidSdkRoot = $env:ANDROID_SDK_ROOT
$previousAndroidHome = $env:ANDROID_HOME
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$failed = $false

try {
    Assert-ServerUrl -Url $DefaultServerUrl

    $repoRoot = Resolve-AbsolutePath -Path (Join-Path $PSScriptRoot '..')
    $clientRoot = Join-Path $repoRoot 'apps\player'
    if (-not (Test-Path -LiteralPath (Join-Path $clientRoot 'pubspec.yaml') -PathType Leaf)) {
        throw "Flutter client project was not found: $clientRoot"
    }

    Write-Step "Repository: $repoRoot"
    $flutterPath = Assert-Flutter
    [void](Assert-Jdk)
    $androidSdkRoot = Assert-AndroidSdk
    if (-not $AndroidOnly) {
        [void](Assert-VisualStudio)
    }
    $androidSigningMode = Get-AndroidReleaseSigningMode

    $androidCacheScript = Join-Path $repoRoot 'scripts\cache-media-kit.ps1'
    $windowsCacheScript = Join-Path $repoRoot 'scripts\cache-media-kit-windows.ps1'
    $cacheScripts = @($androidCacheScript)
    if (-not $AndroidOnly) {
        $cacheScripts += $windowsCacheScript
    }
    foreach ($cacheScript in $cacheScripts) {
        if (-not (Test-Path -LiteralPath $cacheScript -PathType Leaf)) {
            throw "media_kit cache script was not found: $cacheScript"
        }

        Write-Step "Verify offline media_kit cache: $cacheScript"
        & $cacheScript -Offline
    }

    $cacheRepoRoot = $repoRoot
    $buildRepoRoot = $repoRoot
    if (Test-ContainsNonAscii -Value $repoRoot) {
        $substMapping = New-SubstMapping -TargetPath $repoRoot
        $cacheRepoRoot = $substMapping.RootPath
        $buildWorkspace = New-AsciiBuildWorkspace `
            -RepositoryRoot $cacheRepoRoot `
            -WorkspaceBase (Join-Path $cacheRepoRoot 'dist\build-workspaces')
        $buildRepoRoot = $buildWorkspace.RootPath
    }

    $buildClientRoot = Join-Path $buildRepoRoot 'apps\player'
    $buildCacheRoot = Join-Path $cacheRepoRoot 'dist\build-cache'
    $gradleUserHome = Join-Path $buildCacheRoot 'gradle-home'
    $buildTempRoot = Join-Path $buildCacheRoot 'temp'
    New-Item -ItemType Directory -Path $gradleUserHome -Force | Out-Null
    New-Item -ItemType Directory -Path $buildTempRoot -Force | Out-Null
    $env:GRADLE_USER_HOME = $gradleUserHome
    $env:TEMP = $buildTempRoot
    $env:TMP = $buildTempRoot

    $dartDefine = "--dart-define=DEFAULT_SERVER_URL=$DefaultServerUrl"
    Write-Step "DEFAULT_SERVER_URL=$DefaultServerUrl"
    Write-Step "GRADLE_USER_HOME=$gradleUserHome"
    Write-Step "TEMP=$buildTempRoot"

    if ($Clean) {
        Write-Step 'Run full Flutter clean by request'
        Invoke-External -FilePath $flutterPath -Arguments @('clean') -WorkingDirectory $buildClientRoot
    }
    else {
        Write-Step 'Reuse existing Flutter and Gradle build caches'
    }

    if (-not $AndroidOnly) {
        Initialize-WindowsMediaKitArchive -CacheRepositoryRoot $cacheRepoRoot -BuildClientRoot $buildClientRoot
        Invoke-External -FilePath $flutterPath -Arguments @('build', 'windows', '--release', $dartDefine) -WorkingDirectory $buildClientRoot
    }
    Invoke-External -FilePath $flutterPath -Arguments @('build', 'apk', '--release', '--target-platform=android-arm64', $dartDefine) -WorkingDirectory $buildClientRoot

    $apkVerificationScript = Join-Path $repoRoot 'scripts\verify-android-apk.ps1'
    if (-not (Test-Path -LiteralPath $apkVerificationScript -PathType Leaf)) {
        throw "Android APK verification script was not found: $apkVerificationScript"
    }

    $apkPath = Join-Path $buildClientRoot 'build\app\outputs\flutter-apk\app-release.apk'
    Write-Step "Verify Android release APK"
    & $apkVerificationScript -ApkPath $apkPath -AndroidSdkRoot $androidSdkRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Android APK verification failed with exit code $LASTEXITCODE."
    }

    $packageScript = Join-Path $repoRoot 'scripts\package-delivery.ps1'
    if (-not (Test-Path -LiteralPath $packageScript -PathType Leaf)) {
        throw "Delivery packaging script was not found: $packageScript"
    }

    Write-Step "Package delivery artifacts"
    $packageArguments = @{
        RepositoryRoot = $repoRoot
        ArtifactRoot = $buildRepoRoot
        AndroidSigningMode = $androidSigningMode
        AndroidOnly = $AndroidOnly
    }
    & $packageScript @packageArguments
}
catch {
    $failed = $true
    Write-Error "Client build/delivery failed: $($_.Exception.Message)" -ErrorAction Continue
}
finally {
    if ($null -ne $buildWorkspace) {
        $gradleWrapper = Join-Path $buildWorkspace.ClientRoot 'android\gradlew.bat'
        if (Test-Path -LiteralPath $gradleWrapper -PathType Leaf) {
            Write-Step "Stop Gradle daemon in ASCII build workspace"
            try {
                Invoke-External -FilePath $gradleWrapper -Arguments @('--stop') -WorkingDirectory (Split-Path -Parent $gradleWrapper)
            }
            catch {
                Write-Warning "Failed to stop Gradle daemon: $($_.Exception.Message)"
            }
        }
    }

    $env:GRADLE_USER_HOME = $previousGradleUserHome
    $env:ANDROID_SDK_ROOT = $previousAndroidSdkRoot
    $env:ANDROID_HOME = $previousAndroidHome
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp

    if ($null -ne $buildWorkspace) {
        Write-Step "Clean ASCII build workspace: $($buildWorkspace.RootPath)"
        try {
            Remove-AsciiBuildWorkspace `
                -WorkspaceRoot $buildWorkspace.RootPath `
                -WorkspaceBase $buildWorkspace.WorkspaceBase
        }
        catch {
            Write-Warning "Failed to clean ASCII build workspace: $($_.Exception.Message)"
        }
    }

    if ($null -ne $substMapping) {
        Write-Step "Clean temporary drive: $($substMapping.DriveName)"
        & subst.exe $substMapping.DriveName /D
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to clean temporary drive. Run manually: subst $($substMapping.DriveName) /D"
        }
    }
}

if ($failed) {
    exit 1
}
