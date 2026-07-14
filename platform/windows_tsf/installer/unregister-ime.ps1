param(
    [string]$InstallRoot = $PSScriptRoot
)

$ErrorActionPreference = "Stop"

$x64Dll = Join-Path $InstallRoot "x64\PrivatePinyinTsf.dll"
$x86Dll = Join-Path $InstallRoot "x86\PrivatePinyinTsf.dll"
$system32 = if ([Environment]::Is64BitProcess) {
    Join-Path $env:SystemRoot "System32\regsvr32.exe"
} else {
    Join-Path $env:SystemRoot "Sysnative\regsvr32.exe"
}
$sysWow64 = Join-Path $env:SystemRoot "SysWOW64\regsvr32.exe"

if (Test-Path $x64Dll) {
    & $system32 /u /s (Resolve-Path $x64Dll).Path
}
if (Test-Path $x86Dll) {
    & $sysWow64 /u /s (Resolve-Path $x86Dll).Path
}

Write-Host "Unregistered PrivatePinyin TSF DLLs for x64 and x86 applications."
