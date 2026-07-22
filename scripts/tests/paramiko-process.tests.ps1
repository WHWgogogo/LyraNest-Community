Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$libraryPath = Join-Path $PSScriptRoot '..\paramiko-process.ps1'
. (Resolve-Path $libraryPath)

$arguments = New-ParamikoProcessArguments `
    -HelperPath 'scripts\paramiko_deploy.py' `
    -TargetHost 'test-host' `
    -Port 22 `
    -User 'test-user' `
    -LocalPackage 'C:\Temp\package.tar.gz' `
    -RemotePackage '/tmp/package.tar.gz' `
    -CommandFile 'C:\Temp\command.sh' `
    -HostKeyPolicy 'known-hosts' `
    -KnownHostsPath 'C:\Temp\known_hosts' `
    -KeyPath 'C:\Temp\id_ed25519'

if (-not $arguments -or $arguments.Count -eq 0) {
    throw 'Paramiko argument regression: generated argument list is empty.'
}
if ($arguments | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }) {
    throw 'Paramiko argument regression: generated argument list contains an empty value.'
}
if ($arguments -notcontains '--host' -or $arguments -notcontains '--host-key-policy') {
    throw 'Paramiko argument regression: required options are missing.'
}

$testPassword = [Guid]::NewGuid().ToString('N')
$password = ConvertTo-SecureString $testPassword -AsPlainText -Force
$successCode = 'import os,sys; value=os.environ.get("HARMONY_DEPLOY_PASSWORD"); print("stdout-ok"); print("docker-stderr", file=sys.stderr); sys.exit(0 if value and all(value not in argument for argument in sys.argv) else 9)'
Invoke-ParamikoProcess `
    -PythonCommand 'python' `
    -Arguments @('-c', $successCode) `
    -Password $password `
    -DisplayTarget 'local regression success' | Out-Null

$nonZeroCode = 'import sys; print("expected-stderr", file=sys.stderr); sys.exit(7)'
$nonZeroFailedAsExpected = $false
try {
    Invoke-ParamikoProcess `
        -PythonCommand 'python' `
        -Arguments @('-c', $nonZeroCode) `
        -DisplayTarget 'local regression nonzero' | Out-Null
}
catch {
    if ($_.Exception.Message -match 'exit code 7') {
        $nonZeroFailedAsExpected = $true
    }
    else {
        throw
    }
}
if (-not $nonZeroFailedAsExpected) {
    throw 'Paramiko exit-code regression: non-zero child exit was not rejected.'
}

Write-Host 'Paramiko local regression: OK'