param(
    [string]$Configuration = "Release",
    [string]$Generator = "Visual Studio 17 2022",
    [string]$Architecture = "x64",
    [string]$RustTarget = "",
    [string]$BuildDirectory = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (-not $RustTarget) {
    $RustTarget = switch ($Architecture) {
        "x64" { "x86_64-pc-windows-msvc" }
        "Win32" { "i686-pc-windows-msvc" }
        "ARM64" { "aarch64-pc-windows-msvc" }
        default { throw "Unsupported Windows architecture: $Architecture" }
    }
}

if (-not $BuildDirectory) {
    $directoryName = $Architecture.ToLowerInvariant()
    $BuildDirectory = Join-Path $repoRoot "build\windows_tsf\$directoryName"
}

cargo build -p private_pinyin_ime_ffi --release --target $RustTarget --features desktop-ai
if ($LASTEXITCODE -ne 0) {
    throw "Rust FFI build failed for $RustTarget."
}

$rustReleaseDir = Join-Path $repoRoot "target\$RustTarget\release"

$candidateLibs = @(
    (Join-Path $rustReleaseDir "private_pinyin_ime.dll.lib"),
    (Join-Path $rustReleaseDir "private_pinyin_ime.lib")
)

$coreLib = $candidateLibs | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $coreLib) {
    throw "Could not find private_pinyin_ime import library for $RustTarget."
}

cmake -S platform/windows_tsf -B $BuildDirectory -G $Generator -A $Architecture `
    -DPRIVATE_PINYIN_IME_LIB="$coreLib"
if ($LASTEXITCODE -ne 0) {
    throw "CMake configuration failed for $Architecture."
}
cmake --build $BuildDirectory --config $Configuration
if ($LASTEXITCODE -ne 0) {
    throw "CMake build failed for $Architecture."
}

$tsfDll = Get-ChildItem -Path $BuildDirectory -Filter "PrivatePinyinTsf.dll" -Recurse |
    Where-Object { $_.FullName -like "*\$Configuration\*" } |
    Select-Object -First 1
if (-not $tsfDll) {
    throw "Could not find PrivatePinyinTsf.dll under $BuildDirectory after build."
}

Write-Host "Built Windows TSF DLL ($Architecture / $RustTarget): $($tsfDll.FullName)"
