param(
    [string]$Version = "0.1.14",
    [string]$Configuration = "Release",
    [string]$Generator = "Visual Studio 17 2022",
    [string]$Architecture = "x64",
    [string]$SignTool = "",
    [string]$SignCertSubject = "",
    [string]$TimestampUrl = "http://timestamp.digicert.com",
    [switch]$RequireSigning
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

function Resolve-SignTool {
    if ($SignTool) {
        if (-not (Test-Path $SignTool)) {
            throw "SignTool path does not exist: $SignTool"
        }
        return $SignTool
    }

    $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    if ($RequireSigning) {
        throw "signtool.exe is required when -RequireSigning is set."
    }

    Write-Warning "signtool.exe was not found; artifacts will not be signed."
    return $null
}

function Sign-Artifact {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowNull()][string]$ResolvedSignTool
    )

    if (-not $ResolvedSignTool) {
        return
    }

    if (-not $SignCertSubject) {
        if ($RequireSigning) {
            throw "-SignCertSubject is required when -RequireSigning is set."
        }
        Write-Warning "Skipping signing for $Path because -SignCertSubject was not provided."
        return
    }

    & $ResolvedSignTool sign /fd SHA256 /td SHA256 /tr $TimestampUrl /n $SignCertSubject $Path
    if ($LASTEXITCODE -ne 0) {
        throw "Signing failed for $Path."
    }
}

function Resolve-SigningCertificate {
    if (-not $SignCertSubject) {
        if ($RequireSigning) {
            throw "-SignCertSubject is required when -RequireSigning is set."
        }
        Write-Warning "Skipping PowerShell script signing because -SignCertSubject was not provided."
        return $null
    }

    $stores = @("Cert:\CurrentUser\My", "Cert:\LocalMachine\My")
    foreach ($store in $stores) {
        $certificate = Get-ChildItem -Path $store -CodeSigningCert -ErrorAction SilentlyContinue |
            Where-Object { $_.HasPrivateKey -and ($_.Subject -eq $SignCertSubject -or $_.Subject -like "*$SignCertSubject*") } |
            Sort-Object NotAfter -Descending |
            Select-Object -First 1
        if ($certificate) {
            return $certificate
        }
    }

    if ($RequireSigning) {
        throw "Could not find a code-signing certificate matching '$SignCertSubject' in CurrentUser or LocalMachine certificate stores."
    }

    Write-Warning "Could not find a code-signing certificate matching '$SignCertSubject'; PowerShell scripts will not be signed."
    return $null
}

function Sign-PowerShellScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowNull()][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    if (-not $Certificate) {
        return
    }

    $signature = Set-AuthenticodeSignature `
        -FilePath $Path `
        -Certificate $Certificate `
        -TimestampServer $TimestampUrl `
        -HashAlgorithm SHA256

    if ($signature.Status -ne "Valid") {
        throw "PowerShell script signing failed for $($Path): $($signature.StatusMessage)"
    }
}

function Resolve-Wix3Command {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$FallbackBins = @()
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    foreach ($bin in $FallbackBins) {
        if (-not $bin) {
            continue
        }
        $candidate = Join-Path $bin $Name
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Resolve-WixToolchain {
    $wix = Get-Command wix -ErrorAction SilentlyContinue
    if ($wix) {
        return [pscustomobject]@{
            Kind = "WixCli"
            Wix = $wix.Source
            Candle = $null
            Light = $null
        }
    }

    $fallbackBins = @()
    if (${env:ProgramFiles(x86)}) {
        $fallbackBins += (Join-Path ${env:ProgramFiles(x86)} "WiX Toolset v3.14\bin")
        $fallbackBins += (Join-Path ${env:ProgramFiles(x86)} "WiX Toolset v3.11\bin")

        Get-ChildItem -Path ${env:ProgramFiles(x86)} -Directory -Filter "WiX Toolset*" -ErrorAction SilentlyContinue |
            ForEach-Object { $fallbackBins += (Join-Path $_.FullName "bin") }
    }
    if ($env:WIX) {
        $fallbackBins += $env:WIX
    }
    if ($env:ChocolateyInstall) {
        $fallbackBins += (Join-Path $env:ChocolateyInstall "bin")
    }

    $candle = Resolve-Wix3Command -Name "candle.exe" -FallbackBins $fallbackBins
    $light = Resolve-Wix3Command -Name "light.exe" -FallbackBins $fallbackBins
    if ($candle -and $light) {
        return [pscustomobject]@{
            Kind = "Wix3"
            Wix = $null
            Candle = $candle
            Light = $light
        }
    }

    return $null
}

function Resolve-NsisToolchain {
    $command = Get-Command makensis.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $fallbacks = @()
    if (${env:ProgramFiles(x86)}) {
        $fallbacks += (Join-Path ${env:ProgramFiles(x86)} "NSIS\makensis.exe")
    }
    if ($env:ProgramFiles) {
        $fallbacks += (Join-Path $env:ProgramFiles "NSIS\makensis.exe")
    }
    if ($env:ChocolateyInstall) {
        $fallbacks += (Join-Path $env:ChocolateyInstall "bin\makensis.exe")
    }

    foreach ($candidate in $fallbacks) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Build-NsisInstaller {
    param(
        [Parameter(Mandatory = $true)][string]$NsisToolchain,
        [Parameter(Mandatory = $true)][string]$PackageSource,
        [Parameter(Mandatory = $true)][string]$InstallerIcon,
        [Parameter(Mandatory = $true)][string]$ProductVersion,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    & $NsisToolchain `
        "/INPUTCHARSET" `
        "UTF8" `
        "/DPRODUCT_VERSION=$ProductVersion" `
        "/DPACKAGE_SOURCE=$PackageSource" `
        "/DICON_PATH=$InstallerIcon" `
        "/DOUTPUT_PATH=$OutputPath" `
        "platform\windows_tsf\installer\PrivatePinyinTsf.nsi"
    if ($LASTEXITCODE -ne 0) {
        throw "NSIS makensis.exe failed."
    }
}

function Build-Msi {
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$WixToolchain,
        [Parameter(Mandatory = $true)][string]$PackageSource,
        [Parameter(Mandatory = $true)][string]$ProductVersion,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    if ($WixToolchain.Kind -eq "WixCli") {
        & $WixToolchain.Wix build `
            "platform\windows_tsf\installer\PrivatePinyinTsf.wxs" `
            "-dPackageSource=$PackageSource" `
            "-dProductVersion=$ProductVersion" `
            -out $OutputPath
        if ($LASTEXITCODE -ne 0) {
            throw "WiX build failed."
        }
        return
    }

    $wixObjDir = Join-Path $repoRoot "build\windows_tsf\wix"
    New-Item -ItemType Directory -Force -Path $wixObjDir | Out-Null
    $wixObj = Join-Path $wixObjDir "PrivatePinyinTsf.wixobj"
    Remove-Item -Force $wixObj -ErrorAction SilentlyContinue

    & $WixToolchain.Candle `
        "-dPackageSource=$PackageSource" `
        "-dProductVersion=$ProductVersion" `
        "platform\windows_tsf\installer\PrivatePinyinTsf.wxs" `
        -out $wixObj
    if ($LASTEXITCODE -ne 0) {
        throw "WiX candle.exe failed."
    }

    & $WixToolchain.Light $wixObj -out $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "WiX light.exe failed."
    }
}

$resolvedSignTool = Resolve-SignTool
$resolvedSigningCertificate = Resolve-SigningCertificate

& (Join-Path $repoRoot "scripts\build_windows_tsf.ps1") `
    -Configuration $Configuration `
    -Generator $Generator `
    -Architecture $Architecture

cargo build -p private_pinyin_settings --release

$buildDir = Join-Path $repoRoot "build\windows_tsf"
$stageDir = Join-Path $repoRoot "dist\windows_tsf\PrivatePinyin-$Version"
$zipPath = Join-Path $repoRoot "dist\windows_tsf\PrivatePinyin-$Version.zip"
$msiPath = Join-Path $repoRoot "dist\windows_tsf\PrivatePinyin-$Version.msi"
$exePath = Join-Path $repoRoot "dist\windows_tsf\PrivatePinyin-$Version-setup.exe"
$installerIcon = Join-Path $repoRoot "platform\windows_tsf\installer\PrivatePinyinInstaller.ico"

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
if (-not (Test-Path $installerIcon)) {
    throw "Could not find Windows installer icon at $installerIcon."
}

Copy-Item $tsfDll.FullName -Destination $stageDir
Copy-Item $ffiDll -Destination $stageDir
Copy-Item $settingsTool -Destination $stageDir
Copy-Item "platform\windows_tsf\installer\register-ime.ps1" -Destination $stageDir
Copy-Item "platform\windows_tsf\installer\unregister-ime.ps1" -Destination $stageDir
Copy-Item "platform\windows_tsf\installer\open-settings.ps1" -Destination $stageDir
Copy-Item "platform\windows_tsf\installer\open-onboarding.ps1" -Destination $stageDir
Copy-Item $installerIcon -Destination $stageDir
Copy-Item "config\default_settings.json" -Destination $stageDir

Get-ChildItem -Path $stageDir -File |
    Where-Object { $_.Extension -in ".dll", ".exe" } |
    ForEach-Object { Sign-Artifact -Path $_.FullName -ResolvedSignTool $resolvedSignTool }
Get-ChildItem -Path $stageDir -File |
    Where-Object { $_.Extension -eq ".ps1" } |
    ForEach-Object { Sign-PowerShellScript -Path $_.FullName -Certificate $resolvedSigningCertificate }

Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $stageDir "*") -DestinationPath $zipPath
Write-Host "Built Windows installer bundle: $zipPath"

$nsisToolchain = Resolve-NsisToolchain
if ($nsisToolchain) {
    Remove-Item -Force $exePath -ErrorAction SilentlyContinue
    Build-NsisInstaller `
        -NsisToolchain $nsisToolchain `
        -PackageSource $stageDir `
        -InstallerIcon $installerIcon `
        -ProductVersion $Version `
        -OutputPath $exePath
    Sign-Artifact -Path $exePath -ResolvedSignTool $resolvedSignTool
    Write-Host "Built Windows EXE installer: $exePath"
} else {
    if ($RequireSigning) {
        throw "NSIS is required to build the signed release EXE when -RequireSigning is set."
    }
    Write-Warning "NSIS is not installed; skipped EXE installer generation. Install NSIS and rerun this script to build the EXE."
}

$wixToolchain = Resolve-WixToolchain
if ($wixToolchain) {
    Remove-Item -Force $msiPath -ErrorAction SilentlyContinue
    Build-Msi `
        -WixToolchain $wixToolchain `
        -PackageSource $stageDir `
        -ProductVersion $Version `
        -OutputPath $msiPath
    Sign-Artifact -Path $msiPath -ResolvedSignTool $resolvedSignTool
    Write-Host "Built Windows MSI: $msiPath"
} else {
    if ($RequireSigning) {
        throw "WiX is required to build the signed release MSI when -RequireSigning is set."
    }
    Write-Warning "WiX is not installed; skipped MSI generation. Install WiX and rerun this script to build the MSI."
}
