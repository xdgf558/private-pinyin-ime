param(
    [string]$Configuration = "Release",
    [string]$Architecture = "x64",
    [string]$RustTarget = "x86_64-pc-windows-msvc",
    [string]$BuildDirectory = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (-not $BuildDirectory) {
    $BuildDirectory = Join-Path $repoRoot "build\windows_tsf\$($Architecture.ToLowerInvariant())"
}

$probe = Get-ChildItem -Path $BuildDirectory -Filter "PrivatePinyinAIHelperProbe.exe" -Recurse |
    Where-Object { $_.FullName -like "*\$Configuration\*" } |
    Select-Object -First 1
$helper = Join-Path $repoRoot "target\$RustTarget\release\private_pinyin_ai_helper.exe"

if (-not $probe) {
    throw "Could not find the Windows AI Helper probe under $BuildDirectory."
}
if (-not (Test-Path $helper)) {
    throw "Could not find the Windows AI Helper at $helper."
}

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $probe.FullName
$startInfo.UseShellExecute = $false
$startInfo.ArgumentList.Add($helper)
$probeProcess = [System.Diagnostics.Process]::Start($startInfo)
if (-not $probeProcess.WaitForExit(60000)) {
    $probeProcess.Kill($true)
    throw "Windows AI Helper lifecycle probe exceeded the 60-second deadline."
}
if ($probeProcess.ExitCode -ne 0) {
    throw "Windows AI Helper lifecycle probe failed with exit code $($probeProcess.ExitCode)."
}

Write-Host "Windows AI Helper authentication, health, cancellation, crash recovery, and shutdown probe passed."
