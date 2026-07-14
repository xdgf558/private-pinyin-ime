param(
    [string]$InstallRoot = $PSScriptRoot
)

$ErrorActionPreference = "Stop"

$x64Dll = (Resolve-Path (Join-Path $InstallRoot "x64\PrivatePinyinTsf.dll")).Path
$x86Dll = (Resolve-Path (Join-Path $InstallRoot "x86\PrivatePinyinTsf.dll")).Path
$system32 = if ([Environment]::Is64BitProcess) {
    Join-Path $env:SystemRoot "System32\regsvr32.exe"
} else {
    Join-Path $env:SystemRoot "Sysnative\regsvr32.exe"
}
$sysWow64 = Join-Path $env:SystemRoot "SysWOW64\regsvr32.exe"

& $system32 /s $x64Dll
if ($LASTEXITCODE -ne 0) {
    throw "64-bit TSF registration failed with exit code $LASTEXITCODE."
}
& $sysWow64 /s $x86Dll
$x86ExitCode = $LASTEXITCODE
if ($x86ExitCode -ne 0) {
    & $system32 /u /s $x64Dll
    throw "32-bit TSF registration failed with exit code $x86ExitCode."
}

Write-Host "Registered PrivatePinyin TSF DLLs for x64 and x86 applications."
