param(
    [Parameter(Mandatory = $true)][string]$Destination
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$cacheDir = Join-Path $repoRoot "build\writer_runtime\windows-x64-cpu"
$archive = Join-Path $cacheDir "llama-b10069-bin-win-cpu-x64.zip"
$extractDir = Join-Path $cacheDir "extracted"
$url = "https://github.com/ggml-org/llama.cpp/releases/download/b10069/llama-b10069-bin-win-cpu-x64.zip"
$expectedSha = "6c6b235900f2264c9033ede3f0b0f2faac6ba363bd4c885ef672d55309e19662"

New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
if ((-not (Test-Path $archive)) -or ((Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant() -ne $expectedSha)) {
    Remove-Item -Force $archive -ErrorAction SilentlyContinue
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive
}
if ((Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant() -ne $expectedSha) {
    throw "Writer runtime SHA-256 mismatch."
}

Remove-Item -Recurse -Force $extractDir, $Destination -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $extractDir, $Destination | Out-Null
Expand-Archive -Path $archive -DestinationPath $extractDir

$server = Join-Path $extractDir "llama-server.exe"
if (-not (Test-Path $server)) {
    throw "Writer runtime is missing llama-server.exe."
}
Copy-Item $server -Destination $Destination

# The official CPU release chooses the best ggml-cpu variant at runtime. Keep
# every DLL from the pinned archive so older and newer x64 CPUs share one build.
$coreDlls = @(
    "llama-server-impl.dll",
    "llama-common.dll",
    "llama.dll",
    "ggml.dll",
    "ggml-base.dll",
    "libomp140.x86_64.dll",
    "mtmd.dll"
)
foreach ($name in $coreDlls) {
    $source = Join-Path $extractDir $name
    if (-not (Test-Path $source)) {
        throw "Writer runtime is missing $name."
    }
    Copy-Item $source -Destination $Destination
}
Get-ChildItem -Path $extractDir -File -Filter "ggml-cpu-*.dll" |
    ForEach-Object { Copy-Item $_.FullName -Destination $Destination }

Set-Content -Path (Join-Path $Destination "llama.cpp-LICENSE.txt") -Encoding UTF8 -Value @"
llama.cpp is licensed under the MIT License.
Source: https://github.com/ggml-org/llama.cpp
Pinned release: b10069 (178a6c44937154dc4c4eff0d166f4a044c4fceba)
"@

$destinationServer = Join-Path $Destination "llama-server.exe"
$helpOutput = (& $destinationServer --help 2>&1 | Out-String)
foreach ($option in @(
    "--api-key-file",
    "--offline",
    "--no-webui",
    "--log-disable",
    "--parallel",
    "--ctx-size",
    "--batch-size",
    "--ubatch-size"
)) {
    if (-not $helpOutput.Contains($option)) {
        throw "Writer runtime is missing required option: $option"
    }
}

Write-Host "Prepared Windows Writer runtime at $Destination"
