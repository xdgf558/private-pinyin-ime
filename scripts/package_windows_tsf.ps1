param(
    [string]$Version = "0.1.0",
    [string]$Configuration = "Release",
    [string]$Generator = "Visual Studio 17 2022",
    [string]$Architecture = "x64"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

& (Join-Path $repoRoot "scripts\build_windows_tsf.ps1") `
    -Configuration $Configuration `
    -Generator $Generator `
    -Architecture $Architecture

cargo build -p private_pinyin_settings --release

$buildDir = Join-Path $repoRoot "build\windows_tsf"
$stageDir = Join-Path $repoRoot "dist\windows_tsf\PrivatePinyin-$Version"
$zipPath = Join-Path $repoRoot "dist\windows_tsf\PrivatePinyin-$Version.zip"
$msiPath = Join-Path $repoRoot "dist\windows_tsf\PrivatePinyin-$Version.msi"

Remove-Item -Recurse -Force $stageDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

$tsfDll = Get-ChildItem -Path $buildDir -Filter "PrivatePinyinTsf.dll" -Recurse |
    Where-Object { $_.FullName -like "*\$Configuration\*" } |
    Select-Object -First 1
if (-not $tsfDll) {
    throw "Could not find PrivatePinyinTsf.dll under $buildDir."
}

$ffiDll = Join-Path $repoRoot "target\release\private_pinyin_ime.dll"
if (-not (Test-Path $ffiDll)) {
    throw "Could not find Rust FFI DLL at $ffiDll."
}

$settingsTool = Join-Path $repoRoot "target\release\private-pinyin-settings.exe"
if (-not (Test-Path $settingsTool)) {
    throw "Could not find settings tool at $settingsTool."
}

Copy-Item $tsfDll.FullName -Destination $stageDir
Copy-Item $ffiDll -Destination $stageDir
Copy-Item $settingsTool -Destination $stageDir
Copy-Item "platform\windows_tsf\installer\register-ime.ps1" -Destination $stageDir
Copy-Item "platform\windows_tsf\installer\unregister-ime.ps1" -Destination $stageDir
Copy-Item "platform\windows_tsf\installer\open-settings.ps1" -Destination $stageDir
Copy-Item "config\default_settings.json" -Destination $stageDir

Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $stageDir "*") -DestinationPath $zipPath
Write-Host "Built Windows installer bundle: $zipPath"

$wix = Get-Command wix -ErrorAction SilentlyContinue
if ($wix) {
    Remove-Item -Force $msiPath -ErrorAction SilentlyContinue
    & $wix.Source build `
        "platform\windows_tsf\installer\PrivatePinyinTsf.wxs" `
        "-dPackageSource=$stageDir" `
        "-dProductVersion=$Version" `
        -out $msiPath
    Write-Host "Built Windows MSI: $msiPath"
} else {
    Write-Warning "WiX is not installed; skipped MSI generation. Install WiX and rerun this script to build the MSI."
}
