param(
    [string]$Configuration = "Release",
    [string]$Generator = "Visual Studio 17 2022",
    [string]$Architecture = "x64"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

cargo build -p private_pinyin_ime_ffi --release

$candidateLibs = @(
    (Join-Path $repoRoot "target\release\private_pinyin_ime.dll.lib"),
    (Join-Path $repoRoot "target\release\private_pinyin_ime.lib")
)

$coreLib = $candidateLibs | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $coreLib) {
    throw "Could not find private_pinyin_ime import/static library under target\release."
}

$buildDir = Join-Path $repoRoot "build\windows_tsf"
cmake -S platform/windows_tsf -B $buildDir -G $Generator -A $Architecture `
    -DPRIVATE_PINYIN_IME_LIB="$coreLib"
cmake --build $buildDir --config $Configuration

$tsfDll = Get-ChildItem -Path $buildDir -Filter "PrivatePinyinTsf.dll" -Recurse |
    Where-Object { $_.FullName -like "*\$Configuration\*" } |
    Select-Object -First 1
if (-not $tsfDll) {
    throw "Could not find PrivatePinyinTsf.dll under $buildDir after build."
}

Write-Host "Built Windows TSF DLL: $($tsfDll.FullName)"
