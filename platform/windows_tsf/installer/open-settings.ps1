param(
    [string]$SettingsTool = (Join-Path $PSScriptRoot "private-pinyin-settings.exe"),
    [string]$PreviewPath = "",
    [ValidateSet("general", "privacy", "lexicon", "writer", "about")][string]$PreviewTab = "general",
    [string]$InvocationSelfTestDirectory = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http
[System.Windows.Forms.Application]::EnableVisualStyles()

$dataDir = Join-Path $env:LOCALAPPDATA "PrivatePinyin"
$settingsPath = Join-Path $dataDir "settings.json"
$userLexiconPath = Join-Path $dataDir "user_lexicon.sqlite"
$importedLexiconPath = Join-Path $dataDir "imported_lexicon.tsv"
$rimeIceLexiconPath = Join-Path $dataDir "rime_ice.tsv"
$rimeFrostLexiconPath = Join-Path $dataDir "rime_frost.tsv"
$rimeFrostManifestPath = Join-Path $dataDir "rime_frost_manifest.json"
$iconPath = Join-Path $PSScriptRoot "PrivatePinyinInstaller.ico"
$logoPath = Join-Path $PSScriptRoot "PrivatePinyinLogo.png"
$writerScriptPath = Join-Path $PSScriptRoot "open-writer.ps1"
$writerModelPath = Join-Path $dataDir "WriterModels\qwen2.5-1.5b-instruct-q4-k-m\qwen2.5-1.5b-instruct-q4_k_m.gguf"
$writerModelSize = [int64]1117320736
$rimeFrostDisplayName = "白霜拼音核心词库"
$rimeFrostApprovedVersion = "1.0.4"
$rimeFrostArchiveBytes = [int64]44008360
$rimeFrostArchiveSha256 = "4f4998ae83f63d757c0a4ace192f69d48265bddfabe231642b73e3739ed0f2f5"
$rimeFrostArchiveUrl = "https://github.com/gaboolic/rime-frost/releases/download/1.0.4/rime-frost-schemas.zip"
$rimeFrostReleaseUrl = "https://github.com/gaboolic/rime-frost/releases/tag/1.0.4"
$rimeFrostLicenseUrl = "https://github.com/gaboolic/rime-frost/blob/master/LICENSE"
$rimeFrostLatestReleaseApiUrl = "https://api.github.com/repos/gaboolic/rime-frost/releases/latest"
$script:lastSettingsToolError = ""

function Get-DefaultSettingsTemplatePath {
    $candidates = @(
        (Join-Path $PSScriptRoot "default_settings.json"),
        (Join-Path $PSScriptRoot "..\..\..\config\default_settings.json")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "缺少 default_settings.json 默认设置文件。"
}

function Get-AppVersion {
    $versionPath = Join-Path $PSScriptRoot "version.txt"
    if (Test-Path $versionPath) {
        $version = (Get-Content -Raw -Path $versionPath).Trim()
        if ($version) {
            return $version
        }
    }

    $cargoPath = Join-Path $PSScriptRoot "..\..\..\Cargo.toml"
    if (Test-Path $cargoPath) {
        foreach ($line in Get-Content -Path $cargoPath) {
            if ($line -match '^version\s*=\s*"([^"]+)"') {
                return $Matches[1]
            }
        }
    }

    return "开发版"
}

function Get-DefaultSettings {
    $settings = Get-Content -Raw -Path (Get-DefaultSettingsTemplatePath) | ConvertFrom-Json
    $settings.user_lexicon_path = $userLexiconPath.Replace("\", "/")
    $settings.imported_lexicon_path = $importedLexiconPath.Replace("\", "/")
    $settings.rime_ice_lexicon_path = $rimeIceLexiconPath.Replace("\", "/")
    $settings.rime_frost_lexicon_path = $rimeFrostLexiconPath.Replace("\", "/")
    return $settings
}

function Set-JsonProperty($object, [string]$name, $value) {
    if ($null -eq $object.PSObject.Properties[$name]) {
        $object | Add-Member -NotePropertyName $name -NotePropertyValue $value
    } else {
        $object.$name = $value
    }
}

function Ensure-SettingsFile {
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
    if (-not (Test-Path $settingsPath)) {
        $settings = Get-DefaultSettings
        $settings | ConvertTo-Json -Depth 4 | Set-Content -Path $settingsPath -Encoding UTF8
        return
    }

    $settings = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
    $needsWrite = $false
    $expectedUserPath = $userLexiconPath.Replace("\", "/")
    $expectedImportedPath = $importedLexiconPath.Replace("\", "/")
    $expectedRimeIcePath = $rimeIceLexiconPath.Replace("\", "/")
    $expectedRimeFrostPath = $rimeFrostLexiconPath.Replace("\", "/")
    if ($settings.user_lexicon_path -ne $expectedUserPath) {
        $settings.user_lexicon_path = $expectedUserPath
        $needsWrite = $true
    }
    if ($null -eq $settings.PSObject.Properties["imported_lexicon_path"]) {
        $settings | Add-Member -NotePropertyName "imported_lexicon_path" -NotePropertyValue $expectedImportedPath
        $needsWrite = $true
    } elseif ($settings.imported_lexicon_path -ne $expectedImportedPath) {
        $settings.imported_lexicon_path = $expectedImportedPath
        $needsWrite = $true
    }
    if ($null -eq $settings.PSObject.Properties["rime_ice_lexicon_path"] -or
        $settings.rime_ice_lexicon_path -ne $expectedRimeIcePath) {
        Set-JsonProperty $settings "rime_ice_lexicon_path" $expectedRimeIcePath
        $needsWrite = $true
    }
    if ($null -eq $settings.PSObject.Properties["enable_rime_ice_lexicon"]) {
        Set-JsonProperty $settings "enable_rime_ice_lexicon" $false
        $needsWrite = $true
    }
    if ($null -eq $settings.PSObject.Properties["rime_frost_lexicon_path"] -or
        $settings.rime_frost_lexicon_path -ne $expectedRimeFrostPath) {
        Set-JsonProperty $settings "rime_frost_lexicon_path" $expectedRimeFrostPath
        $needsWrite = $true
    }
    if ($null -eq $settings.PSObject.Properties["enable_rime_frost_lexicon"]) {
        Set-JsonProperty $settings "enable_rime_frost_lexicon" $true
        $needsWrite = $true
    }
    if ($needsWrite) {
        $settings | ConvertTo-Json -Depth 4 | Set-Content -Path $settingsPath -Encoding UTF8
    }
}

function Read-Settings {
    Ensure-SettingsFile
    Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
}

function Write-Settings($settings) {
    $tmpPath = "$settingsPath.tmp"
    $settings | ConvertTo-Json -Depth 4 | Set-Content -Path $tmpPath -Encoding UTF8
    Move-Item -Force -Path $tmpPath -Destination $settingsPath
}

function Get-BoundedErrorDetail {
    param(
        [AllowEmptyString()][string]$Message,
        [string]$Fallback = "未提供详细错误"
    )

    $detail = $Message.Trim()
    if (-not $detail) {
        $detail = $Fallback
    }
    if ($detail.Length -gt 400) {
        $detail = $detail.Substring(0, 400)
    }
    return $detail
}

function Run-SettingsTool($arguments) {
    $script:lastSettingsToolError = ""
    if (-not (Test-Path $SettingsTool)) {
        $script:lastSettingsToolError = "没有找到词库工具。"
        [System.Windows.Forms.MessageBox]::Show(
            "没有找到词库工具：$SettingsTool",
            "猫栈拼音",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $false
    }

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Start-Process joins ArgumentList into one command line and can split
        # profile or temp paths containing spaces. The call operator preserves
        # each array element as one native argument. Continue keeps native
        # stderr in the captured output so nonzero exits behave consistently on
        # Windows PowerShell versions that otherwise raise NativeCommandError.
        $ErrorActionPreference = "Continue"
        $output = @(& $SettingsTool @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } catch {
        $script:lastSettingsToolError = Get-BoundedErrorDetail -Message $_.Exception.Message
        return $false
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -eq 0) {
        return $true
    }

    $detail = (($output | ForEach-Object { ([string]$_).Trim() }) |
        Where-Object { $_ }) -join " "
    $script:lastSettingsToolError = Get-BoundedErrorDetail `
        -Message $detail `
        -Fallback "词库工具退出码 $exitCode"
    return $false
}

# This production-safe self-test must remain after Run-SettingsTool and before
# settings initialization because CI launches the shipped script directly.
if ($InvocationSelfTestDirectory) {
    New-Item -ItemType Directory -Force -Path $InvocationSelfTestDirectory | Out-Null
    $testSettingsPath = Join-Path $InvocationSelfTestDirectory "settings with spaces.json"
    $testFrostPath = Join-Path $InvocationSelfTestDirectory "frost layer with spaces.tsv"
    $ok = Run-SettingsTool @(
        "write-default",
        "--settings", $testSettingsPath,
        "--rime-frost-lexicon", $testFrostPath
    )
    if (-not $ok -or -not (Test-Path $testSettingsPath)) {
        throw "Settings-tool argument self-test failed: $script:lastSettingsToolError"
    }
    $failedAsExpected = -not (Run-SettingsTool @("__invalid_self_test_command__"))
    if (-not $failedAsExpected -or
        -not $script:lastSettingsToolError -or
        $script:lastSettingsToolError -notmatch "usage:") {
        throw "Settings-tool failure-reporting self-test failed: $script:lastSettingsToolError"
    }
    Write-Host "Settings-tool success and failure self-tests passed."
    exit 0
}

function Get-RimeFrostManifest {
    if (-not (Test-Path $rimeFrostManifestPath)) {
        return $null
    }
    try {
        return Get-Content -Raw -Path $rimeFrostManifestPath | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Write-RimeFrostManifest {
    $manifest = [ordered]@{
        schema_version = 1
        display_name = $rimeFrostDisplayName
        version = $rimeFrostApprovedVersion
        release_url = $rimeFrostReleaseUrl
        archive_sha256 = $rimeFrostArchiveSha256
        imported_at = [DateTime]::UtcNow.ToString("o")
    }
    $temporary = "$rimeFrostManifestPath.tmp"
    $manifest | ConvertTo-Json | Set-Content -Path $temporary -Encoding UTF8
    Move-Item -Force -Path $temporary -Destination $rimeFrostManifestPath
}

function Get-RimeFrostSummary {
    if (-not (Test-Path $rimeFrostLexiconPath)) {
        return "当前白霜拼音：尚未导入"
    }
    $manifest = Get-RimeFrostManifest
    $version = if ($null -ne $manifest -and $manifest.version) {
        [string]$manifest.version
    } else {
        "本地数据（来源记录不可用）"
    }
    $current = Read-Settings
    $suffix = if ([bool]$current.enable_rime_frost_lexicon) { "" } else { "（已停用）" }
    return "当前白霜拼音：$version$suffix"
}

function New-OfficialHttpClient {
    # Windows PowerShell can inherit legacy .NET TLS defaults even when Chrome
    # reaches GitHub successfully. Preserve modern SystemDefault negotiation;
    # only legacy explicit protocol sets need TLS 1.2 added.
    $currentProtocol = [System.Net.ServicePointManager]::SecurityProtocol
    $tls12 = [System.Net.SecurityProtocolType]::Tls12
    if ([int]$currentProtocol -ne 0 -and
        (([int]$currentProtocol -band [int]$tls12) -eq 0)) {
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.SecurityProtocolType]([int]$currentProtocol -bor [int]$tls12)
    }
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $true
    $handler.MaxAutomaticRedirections = 5
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromMinutes(5)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd("StationCat-PrivatePinyin")
    return $client
}

function Download-ApprovedRimeFrostArchive {
    $client = New-OfficialHttpClient
    $response = $null
    $temporary = Join-Path ([System.IO.Path]::GetTempPath()) ("rime-frost-" + [Guid]::NewGuid().ToString("N") + ".zip")
    try {
        $response = $client.GetAsync(
            $rimeFrostArchiveUrl,
            [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
        ).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw "GitHub 返回 HTTP $([int]$response.StatusCode)"
        }
        $finalUri = $response.RequestMessage.RequestUri
        if ($finalUri.Scheme -ne [System.Uri]::UriSchemeHttps) {
            throw "下载被重定向到非 HTTPS 地址"
        }
        $declaredLength = $response.Content.Headers.ContentLength
        if ($null -ne $declaredLength -and [int64]$declaredLength -ne $rimeFrostArchiveBytes) {
            throw "下载文件大小与审核清单不一致"
        }
        $source = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $destination = [System.IO.File]::Open(
            $temporary,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        try {
            $buffer = New-Object byte[] (64 * 1024)
            [int64]$totalBytes = 0
            while (($read = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $totalBytes += $read
                if ($totalBytes -gt $rimeFrostArchiveBytes) {
                    throw "下载文件超过审核清单大小"
                }
                $destination.Write($buffer, 0, $read)
            }
        } finally {
            $destination.Dispose()
            $source.Dispose()
        }
        if ((Get-Item $temporary).Length -ne $rimeFrostArchiveBytes) {
            throw "下载文件大小与审核清单不一致"
        }
        return $temporary
    } catch {
        Remove-Item -Force -ErrorAction SilentlyContinue $temporary
        throw
    } finally {
        if ($null -ne $response) {
            $response.Dispose()
        }
        $client.Dispose()
    }
}

function Get-LatestRimeFrostVersion {
    $client = New-OfficialHttpClient
    $response = $null
    try {
        $response = $client.GetAsync($rimeFrostLatestReleaseApiUrl).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode -or
            $response.RequestMessage.RequestUri.Host.ToLowerInvariant() -ne "api.github.com") {
            throw "无法读取官方版本信息"
        }
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $release = $body | ConvertFrom-Json
        $normalized = ([string]$release.tag_name).Trim()
        if ($normalized.StartsWith("v", [System.StringComparison]::OrdinalIgnoreCase)) {
            $normalized = $normalized.Substring(1)
        }
        return $normalized
    } finally {
        if ($null -ne $response) {
            $response.Dispose()
        }
        $client.Dispose()
    }
}

$colors = @{
    Header = [System.Drawing.Color]::FromArgb(24, 69, 71)
    Accent = [System.Drawing.Color]::FromArgb(242, 181, 62)
    Text = [System.Drawing.Color]::FromArgb(30, 36, 38)
    Muted = [System.Drawing.Color]::FromArgb(92, 102, 106)
    Border = [System.Drawing.Color]::FromArgb(217, 222, 223)
    Surface = [System.Drawing.Color]::FromArgb(247, 249, 249)
    Success = [System.Drawing.Color]::FromArgb(30, 122, 76)
    Danger = [System.Drawing.Color]::FromArgb(178, 61, 54)
    White = [System.Drawing.Color]::White
}

function New-UiFont {
    param(
        [float]$Size,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )

    New-Object System.Drawing.Font -ArgumentList @("Microsoft YaHei UI", $Size, $Style, [System.Drawing.GraphicsUnit]::Point)
}

function New-UiLabel {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [float]$Size = 9,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular,
        [System.Drawing.Color]$Color = $colors.Text
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, $Height)
    $label.Font = New-UiFont -Size $Size -Style $Style
    $label.ForeColor = $Color
    $label.BackColor = [System.Drawing.Color]::Transparent
    $Parent.Controls.Add($label)
    return $label
}

function Add-Separator {
    param([System.Windows.Forms.Control]$Parent, [int]$Y)

    $line = New-Object System.Windows.Forms.Panel
    $line.Location = New-Object System.Drawing.Point(22, $Y)
    $line.Size = New-Object System.Drawing.Size(670, 1)
    $line.BackColor = $colors.Border
    $Parent.Controls.Add($line)
}

function New-DropDown {
    param(
        [System.Windows.Forms.Control]$Parent,
        [int]$Y,
        [string[]]$Items
    )

    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.Location = New-Object System.Drawing.Point(235, $Y)
    $combo.Size = New-Object System.Drawing.Size(220, 30)
    $combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $combo.Font = New-UiFont -Size 9
    [void]$combo.Items.AddRange($Items)
    $Parent.Controls.Add($combo)
    return $combo
}

Ensure-SettingsFile
$settings = Read-Settings
$appVersion = Get-AppVersion

$form = New-Object System.Windows.Forms.Form
$form.Text = "猫栈拼音偏好设置"
$form.StartPosition = "CenterScreen"
$form.ClientSize = New-Object System.Drawing.Size(780, 620)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.BackColor = $colors.White
$form.Font = New-UiFont -Size 9

if (Test-Path $iconPath) {
    $form.Icon = New-Object System.Drawing.Icon($iconPath)
}

$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size(780, 92)
$header.BackColor = $colors.Header
$form.Controls.Add($header)

if (Test-Path $logoPath) {
    $headerIcon = New-Object System.Windows.Forms.PictureBox
    $headerIcon.Location = New-Object System.Drawing.Point(28, 20)
    $headerIcon.Size = New-Object System.Drawing.Size(52, 52)
    $headerIcon.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $headerIcon.Image = [System.Drawing.Image]::FromFile($logoPath)
    $header.Controls.Add($headerIcon)
}

[void](New-UiLabel -Parent $header -Text "猫栈拼音" -X 96 -Y 20 -Width 300 -Height 34 -Size 18 -Style ([System.Drawing.FontStyle]::Bold) -Color $colors.White)
[void](New-UiLabel -Parent $header -Text "偏好设置" -X 98 -Y 55 -Width 220 -Height 22 -Size 9 -Color ([System.Drawing.Color]::FromArgb(216, 231, 231)))
$headerVersion = New-UiLabel -Parent $header -Text "版本 $appVersion" -X 630 -Y 34 -Width 118 -Height 24 -Size 9 -Style ([System.Drawing.FontStyle]::Bold) -Color $colors.Accent
$headerVersion.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(24, 112)
$tabs.Size = New-Object System.Drawing.Size(732, 430)
$tabs.Font = New-UiFont -Size 9
$tabs.Padding = New-Object System.Drawing.Point(18, 7)
$form.Controls.Add($tabs)

$generalPage = New-Object System.Windows.Forms.TabPage
$generalPage.Text = "常规"
$generalPage.BackColor = $colors.White
$tabs.TabPages.Add($generalPage)

[void](New-UiLabel -Parent $generalPage -Text "输入习惯" -X 22 -Y 22 -Width 180 -Height 26 -Size 11 -Style ([System.Drawing.FontStyle]::Bold))
[void](New-UiLabel -Parent $generalPage -Text "默认输入模式" -X 24 -Y 64 -Width 170 -Height 26 -Size 9)
$defaultMode = New-DropDown -Parent $generalPage -Y 59 -Items @("中文", "英文")
$defaultMode.SelectedIndex = if ([string]$settings.default_mode -eq "English") { 1 } else { 0 }

[void](New-UiLabel -Parent $generalPage -Text "中英文切换" -X 24 -Y 112 -Width 170 -Height 26 -Size 9)
$toggleKey = New-DropDown -Parent $generalPage -Y 107 -Items @("单按 Shift", "Ctrl + Space")
$toggleKey.SelectedIndex = if ([string]$settings.toggle_key -eq "CtrlSpace") { 1 } else { 0 }
[void](New-UiLabel -Parent $generalPage -Text "单按 Shift 仅在没有组合其他按键时切换。" -X 235 -Y 140 -Width 420 -Height 22 -Size 8 -Color $colors.Muted)

Add-Separator -Parent $generalPage -Y 176
[void](New-UiLabel -Parent $generalPage -Text "候选与外观" -X 22 -Y 196 -Width 180 -Height 26 -Size 11 -Style ([System.Drawing.FontStyle]::Bold))

$prediction = New-Object System.Windows.Forms.CheckBox
$prediction.Text = "显示预测候选"
$prediction.Location = New-Object System.Drawing.Point(24, 238)
$prediction.Size = New-Object System.Drawing.Size(190, 28)
$prediction.Font = New-UiFont -Size 9
$prediction.Checked = [bool]$settings.enable_prediction
$generalPage.Controls.Add($prediction)

$correctionEnabled = $true
if ($null -ne $settings.PSObject.Properties["ai"] -and
    $null -ne $settings.ai -and
    $null -ne $settings.ai.PSObject.Properties["enable_pinyin_correction"]) {
    $correctionEnabled = [bool]$settings.ai.enable_pinyin_correction
}
$pinyinCorrection = New-Object System.Windows.Forms.CheckBox
$pinyinCorrection.Text = "拼音智能纠错"
$pinyinCorrection.Location = New-Object System.Drawing.Point(385, 238)
$pinyinCorrection.Size = New-Object System.Drawing.Size(190, 28)
$pinyinCorrection.Font = New-UiFont -Size 9
$pinyinCorrection.Checked = $correctionEnabled
$generalPage.Controls.Add($pinyinCorrection)

$fuzzyPinyinKeys = @("zh_z", "ch_c", "sh_s", "n_l", "an_ang", "en_eng", "in_ing")
$tolerantPinyinEnabled = $false
if ($null -ne $settings.PSObject.Properties["fuzzy_pinyin"] -and
    $null -ne $settings.fuzzy_pinyin) {
    foreach ($key in $fuzzyPinyinKeys) {
        if ($null -ne $settings.fuzzy_pinyin.PSObject.Properties[$key] -and
            [bool]$settings.fuzzy_pinyin.$key) {
            $tolerantPinyinEnabled = $true
            break
        }
    }
}
$initialTolerantPinyinEnabled = $tolerantPinyinEnabled
$tolerantPinyin = New-Object System.Windows.Forms.CheckBox
$tolerantPinyin.Text = "宽容拼音（常见模糊音）"
$tolerantPinyin.Location = New-Object System.Drawing.Point(385, 270)
$tolerantPinyin.Size = New-Object System.Drawing.Size(220, 28)
$tolerantPinyin.Font = New-UiFont -Size 9
$tolerantPinyin.Checked = $tolerantPinyinEnabled
$generalPage.Controls.Add($tolerantPinyin)

[void](New-UiLabel -Parent $generalPage -Text "每页候选数量" -X 24 -Y 318 -Width 170 -Height 26 -Size 9)
$candidatePageSize = New-Object System.Windows.Forms.NumericUpDown
$candidatePageSize.Location = New-Object System.Drawing.Point(235, 313)
$candidatePageSize.Size = New-Object System.Drawing.Size(90, 28)
$candidatePageSize.Minimum = 3
$candidatePageSize.Maximum = 9
$candidatePageSize.Value = [decimal][int]$settings.candidate_page_size
$generalPage.Controls.Add($candidatePageSize)

[void](New-UiLabel -Parent $generalPage -Text "候选字号" -X 24 -Y 366 -Width 170 -Height 26 -Size 9)
$candidateFontSize = New-Object System.Windows.Forms.NumericUpDown
$candidateFontSize.Location = New-Object System.Drawing.Point(235, 361)
$candidateFontSize.Size = New-Object System.Drawing.Size(90, 28)
$candidateFontSize.Minimum = 10
$candidateFontSize.Maximum = 24
$candidateFontSize.Value = [decimal][int]$settings.candidate_font_size
$generalPage.Controls.Add($candidateFontSize)

[void](New-UiLabel -Parent $generalPage -Text "界面主题" -X 385 -Y 318 -Width 120 -Height 26 -Size 9)
$theme = New-Object System.Windows.Forms.ComboBox
$theme.Location = New-Object System.Drawing.Point(505, 313)
$theme.Size = New-Object System.Drawing.Size(160, 30)
$theme.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$theme.Font = New-UiFont -Size 9
[void]$theme.Items.AddRange(@("跟随系统", "浅色", "深色"))
$theme.SelectedIndex = switch ([string]$settings.theme) {
    "light" { 1 }
    "dark" { 2 }
    default { 0 }
}
$generalPage.Controls.Add($theme)

$privacyPage = New-Object System.Windows.Forms.TabPage
$privacyPage.Text = "隐私与词库"
$privacyPage.BackColor = $colors.White
$privacyPage.AutoScroll = $true
$tabs.TabPages.Add($privacyPage)

$privacy = New-Object System.Windows.Forms.CheckBox
$privacy.Text = "严格隐私模式"
$privacy.Location = New-Object System.Drawing.Point(24, 28)
$privacy.Size = New-Object System.Drawing.Size(220, 28)
$privacy.Font = New-UiFont -Size 10 -Style ([System.Drawing.FontStyle]::Bold)
$privacy.Checked = [bool]$settings.strict_privacy_mode
$privacyPage.Controls.Add($privacy)
[void](New-UiLabel -Parent $privacyPage -Text "停止用户学习与统计；无状态的本地候选重排与拼音纠错仍可使用，输入内容不会上传。" -X 46 -Y 59 -Width 650 -Height 24 -Size 8 -Color $colors.Muted)

$learning = New-Object System.Windows.Forms.CheckBox
$learning.Text = "启用用户学习"
$learning.Location = New-Object System.Drawing.Point(24, 98)
$learning.Size = New-Object System.Drawing.Size(220, 28)
$learning.Font = New-UiFont -Size 10 -Style ([System.Drawing.FontStyle]::Bold)
$learning.Checked = [bool]$settings.enable_user_learning
$privacyPage.Controls.Add($learning)
[void](New-UiLabel -Parent $privacyPage -Text "仅在本机记录你的选词习惯。" -X 46 -Y 129 -Width 600 -Height 24 -Size 8 -Color $colors.Muted)

Add-Separator -Parent $privacyPage -Y 170
[void](New-UiLabel -Parent $privacyPage -Text "用户词库" -X 22 -Y 190 -Width 180 -Height 26 -Size 11 -Style ([System.Drawing.FontStyle]::Bold))
[void](New-UiLabel -Parent $privacyPage -Text "词库位置" -X 24 -Y 238 -Width 100 -Height 24 -Size 9 -Color $colors.Muted)
$lexiconPathLabel = New-UiLabel -Parent $privacyPage -Text $userLexiconPath -X 124 -Y 238 -Width 540 -Height 40 -Size 8 -Color $colors.Text
$lexiconPathLabel.AutoEllipsis = $true

$export = New-Object System.Windows.Forms.Button
$export.Text = "导出词库..."
$export.Location = New-Object System.Drawing.Point(24, 298)
$export.Size = New-Object System.Drawing.Size(130, 36)
$export.Font = New-UiFont -Size 9
$privacyPage.Controls.Add($export)

$clear = New-Object System.Windows.Forms.Button
$clear.Text = "清空词库"
$clear.Location = New-Object System.Drawing.Point(166, 298)
$clear.Size = New-Object System.Drawing.Size(120, 36)
$clear.Font = New-UiFont -Size 9
$clear.ForeColor = $colors.Danger
$privacyPage.Controls.Add($clear)

$openJson = New-Object System.Windows.Forms.Button
$openJson.Text = "打开配置文件"
$openJson.Location = New-Object System.Drawing.Point(298, 298)
$openJson.Size = New-Object System.Drawing.Size(140, 36)
$openJson.Font = New-UiFont -Size 9
$privacyPage.Controls.Add($openJson)

Add-Separator -Parent $privacyPage -Y 352
[void](New-UiLabel -Parent $privacyPage -Text "本地导入词库" -X 22 -Y 370 -Width 180 -Height 26 -Size 11 -Style ([System.Drawing.FontStyle]::Bold))
[void](New-UiLabel -Parent $privacyPage -Text "支持带明确拼音列的 Rime YAML；与内置词库分层保存，升级不会覆盖。" -X 24 -Y 401 -Width 650 -Height 24 -Size 8 -Color $colors.Muted)
$importedPathLabel = New-UiLabel -Parent $privacyPage -Text $importedLexiconPath -X 24 -Y 430 -Width 640 -Height 24 -Size 8 -Color $colors.Text
$importedPathLabel.AutoEllipsis = $true

$importRime = New-Object System.Windows.Forms.Button
$importRime.Text = "导入 Rime..."
$importRime.Location = New-Object System.Drawing.Point(24, 466)
$importRime.Size = New-Object System.Drawing.Size(140, 36)
$importRime.Font = New-UiFont -Size 9
$privacyPage.Controls.Add($importRime)

$clearImported = New-Object System.Windows.Forms.Button
$clearImported.Text = "清空导入词库"
$clearImported.Location = New-Object System.Drawing.Point(176, 466)
$clearImported.Size = New-Object System.Drawing.Size(140, 36)
$clearImported.Font = New-UiFont -Size 9
$clearImported.ForeColor = $colors.Danger
$privacyPage.Controls.Add($clearImported)

$lexiconPage = New-Object System.Windows.Forms.TabPage
$lexiconPage.Text = "白霜词库"
$lexiconPage.BackColor = $colors.White
$tabs.TabPages.Add($lexiconPage)

[void](New-UiLabel -Parent $lexiconPage -Text "白霜拼音核心词库" -X 24 -Y 24 -Width 320 -Height 32 -Size 15 -Style ([System.Drawing.FontStyle]::Bold))
[void](New-UiLabel -Parent $lexiconPage -Text "仅从 gaboolic/rime-frost 官方 GitHub Release 下载 Owner 审核的稳定版。文件大小、SHA-256 与 ZIP 安全边界均会校验。" -X 26 -Y 64 -Width 650 -Height 50 -Size 9 -Color $colors.Muted)

$rimeFrostStatus = New-UiLabel -Parent $lexiconPage -Text "" -X 26 -Y 126 -Width 650 -Height 54 -Size 9 -Style ([System.Drawing.FontStyle]::Bold) -Color $colors.Header

$rimeFrostImport = New-Object System.Windows.Forms.Button
$rimeFrostImport.Text = "导入白霜"
$rimeFrostImport.Location = New-Object System.Drawing.Point(26, 198)
$rimeFrostImport.Size = New-Object System.Drawing.Size(138, 40)
$rimeFrostImport.Font = New-UiFont -Size 9 -Style ([System.Drawing.FontStyle]::Bold)
$rimeFrostImport.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$rimeFrostImport.FlatAppearance.BorderSize = 0
$rimeFrostImport.BackColor = $colors.Accent
$rimeFrostImport.ForeColor = $colors.Text
$lexiconPage.Controls.Add($rimeFrostImport)

$rimeFrostEnable = New-Object System.Windows.Forms.Button
$rimeFrostEnable.Text = "停用"
$rimeFrostEnable.Location = New-Object System.Drawing.Point(176, 198)
$rimeFrostEnable.Size = New-Object System.Drawing.Size(100, 40)
$rimeFrostEnable.Font = New-UiFont -Size 9
$lexiconPage.Controls.Add($rimeFrostEnable)

$rimeFrostClear = New-Object System.Windows.Forms.Button
$rimeFrostClear.Text = "清除"
$rimeFrostClear.Location = New-Object System.Drawing.Point(288, 198)
$rimeFrostClear.Size = New-Object System.Drawing.Size(100, 40)
$rimeFrostClear.Font = New-UiFont -Size 9
$rimeFrostClear.ForeColor = $colors.Danger
$lexiconPage.Controls.Add($rimeFrostClear)

$rimeFrostCheck = New-Object System.Windows.Forms.Button
$rimeFrostCheck.Text = "检查新版"
$rimeFrostCheck.Location = New-Object System.Drawing.Point(400, 198)
$rimeFrostCheck.Size = New-Object System.Drawing.Size(120, 40)
$rimeFrostCheck.Font = New-UiFont -Size 9
$lexiconPage.Controls.Add($rimeFrostCheck)

Add-Separator -Parent $lexiconPage -Y 270
[void](New-UiLabel -Parent $lexiconPage -Text "许可与分层" -X 24 -Y 292 -Width 180 -Height 28 -Size 11 -Style ([System.Drawing.FontStyle]::Bold))
[void](New-UiLabel -Parent $lexiconPage -Text "白霜拼音采用 GPL-3.0。导入只在你明确确认后进行，并写入独立的 rime_frost.tsv；不会覆盖内置词库、手动导入词库、雾凇词库或用户学习数据。" -X 26 -Y 332 -Width 650 -Height 58 -Size 9 -Color $colors.Muted)

$rimeFrostLicense = New-Object System.Windows.Forms.LinkLabel
$rimeFrostLicense.Text = "查看 GPL-3.0 许可与官方 Release"
$rimeFrostLicense.Location = New-Object System.Drawing.Point(26, 386)
$rimeFrostLicense.Size = New-Object System.Drawing.Size(320, 24)
$rimeFrostLicense.Font = New-UiFont -Size 9
$rimeFrostLicense.LinkColor = $colors.Header
$rimeFrostLicense.Add_LinkClicked({ Start-Process $rimeFrostLicenseUrl })
$lexiconPage.Controls.Add($rimeFrostLicense)

function Refresh-RimeFrostSummary {
    $installed = Test-Path $rimeFrostLexiconPath
    $current = Read-Settings
    $enabled = [bool]$current.enable_rime_frost_lexicon
    $rimeFrostStatus.Text = Get-RimeFrostSummary
    $rimeFrostImport.Text = if ($installed) { "重新导入" } else { "导入白霜" }
    $rimeFrostEnable.Text = if ($enabled) { "停用" } else { "启用" }
    $rimeFrostEnable.Enabled = $installed
    $rimeFrostClear.Enabled = $installed
}

$rimeFrostImport.Add_Click({
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "白霜拼音由 gaboolic/rime-frost 项目提供，采用 GPL-3.0 许可。`r`n`r`n猫栈只会从官方 GitHub Release 下载经 Owner 审核的 1.0.4，并校验文件大小、SHA-256 与 ZIP 安全边界。`r`n`r`n选择「是」表示同意 GPL-3.0 并导入；选择「否」打开许可页面。",
        "导入白霜拼音 1.0.4",
        [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    if ($answer -eq [System.Windows.Forms.DialogResult]::No) {
        Start-Process $rimeFrostLicenseUrl
        return
    }
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    $rimeFrostImport.Enabled = $false
    $rimeFrostStatus.Text = "正在从白霜拼音官方 GitHub Release 下载..."
    [System.Windows.Forms.Application]::DoEvents()
    $archive = $null
    $failureStage = "下载"
    try {
        $archive = Download-ApprovedRimeFrostArchive
        $failureStage = "文件校验与词库解析"
        $ok = Run-SettingsTool @(
            "import-rime-frost",
            "--settings", $settingsPath,
            "--input", $archive
        )
        if (-not $ok) {
            $toolDetail = if ($script:lastSettingsToolError) {
                $script:lastSettingsToolError
            } else {
                "词库工具未返回详细错误"
            }
            throw "归档校验或词库解析失败：$toolDetail"
        }

        $failureStage = "启用与来源记录"
        $metadataProblems = New-Object System.Collections.Generic.List[string]
        $enabled = Run-SettingsTool @(
            "set-rime-frost-enabled",
            "--settings", $settingsPath,
            "--enabled", "true"
        )
        if (-not $enabled) {
            $metadataProblems.Add("启用设置写入失败，可稍后手动启用。")
        }
        try {
            Write-RimeFrostManifest
        } catch {
            $metadataProblems.Add("来源记录写入失败，词库数据仍已导入。")
        }
        $script:settings = Read-Settings
        if ($metadataProblems.Count -eq 0) {
            $statusLabel.Text = "白霜拼音 1.0.4 已导入，重新切换一次输入法后生效"
            $statusLabel.ForeColor = $colors.Success
        } else {
            $detail = $metadataProblems -join " "
            $statusLabel.Text = "白霜拼音词库已导入；$detail"
            $statusLabel.ForeColor = $colors.Accent
            [System.Windows.Forms.MessageBox]::Show(
                "白霜拼音词库数据已经导入。$detail",
                "猫栈拼音",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    } catch {
        $detail = Get-BoundedErrorDetail -Message $_.Exception.Message
        $statusLabel.Text = "白霜拼音导入失败，旧词库已保留"
        $statusLabel.ForeColor = $colors.Danger
        $networkHint = if ($failureStage -eq "下载") {
            "`r`n`r`n提示：浏览器和 PowerShell 可能使用不同代理，请确认 Windows 系统代理也能访问 GitHub Release。"
        } else {
            ""
        }
        [System.Windows.Forms.MessageBox]::Show(
            "无法导入白霜拼音。`r`n`r`n失败阶段：$failureStage`r`n原因：$detail$networkHint`r`n`r`n已有白霜词库未被覆盖。",
            "猫栈拼音",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    } finally {
        if ($archive) {
            Remove-Item -Force -ErrorAction SilentlyContinue $archive
        }
        $rimeFrostImport.Enabled = $true
        Refresh-RimeFrostSummary
    }
})

$rimeFrostEnable.Add_Click({
    $enable = -not [bool](Read-Settings).enable_rime_frost_lexicon
    $ok = Run-SettingsTool @(
        "set-rime-frost-enabled",
        "--settings", $settingsPath,
        "--enabled", $enable.ToString().ToLowerInvariant()
    )
    $script:settings = Read-Settings
    $statusLabel.Text = if ($ok) {
        if ($enable) { "白霜拼音已启用" } else { "白霜拼音已停用" }
    } else {
        "无法更新白霜拼音状态"
    }
    $statusLabel.ForeColor = if ($ok) { $colors.Success } else { $colors.Danger }
    Refresh-RimeFrostSummary
})

$rimeFrostClear.Add_Click({
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "只会删除白霜拼音独立词库层，不影响内置词库、手动导入、雾凇或用户学习数据。",
        "清除白霜拼音？",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }
    $ok = Run-SettingsTool @("clear-rime-frost", "--settings", $settingsPath)
    if ($ok -and (Test-Path $rimeFrostManifestPath)) {
        Remove-Item -Force $rimeFrostManifestPath
    }
    $statusLabel.Text = if ($ok) { "白霜拼音已清除" } else { "无法清除白霜拼音" }
    $statusLabel.ForeColor = if ($ok) { $colors.Success } else { $colors.Danger }
    Refresh-RimeFrostSummary
})

$rimeFrostCheck.Add_Click({
    $rimeFrostCheck.Enabled = $false
    $rimeFrostStatus.Text = "正在检查白霜拼音官方稳定版..."
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $latest = Get-LatestRimeFrostVersion
        if ($latest -eq $rimeFrostApprovedVersion) {
            $rimeFrostStatus.Text = "$(Get-RimeFrostSummary)；审核清单已是最新版"
        } else {
            $rimeFrostStatus.Text = "发现上游 $latest；新版待审核。当前仅允许导入 $rimeFrostApprovedVersion。"
        }
    } catch {
        $rimeFrostStatus.Text = "无法检查白霜拼音版本，请稍后重试。"
    } finally {
        $rimeFrostCheck.Enabled = $true
    }
})

Refresh-RimeFrostSummary

$writerPage = New-Object System.Windows.Forms.TabPage
$writerPage.Text = "本地 Writer"
$writerPage.BackColor = $colors.White
$tabs.TabPages.Add($writerPage)

[void](New-UiLabel -Parent $writerPage -Text "Writer 高级功能" -X 24 -Y 24 -Width 300 -Height 32 -Size 15 -Style ([System.Drawing.FontStyle]::Bold))
[void](New-UiLabel -Parent $writerPage -Text "对你主动提交的文字进行本地改写和翻译。普通拼音与 AI Lite 不依赖 Writer。" -X 26 -Y 64 -Width 650 -Height 44 -Size 9 -Color $colors.Muted)

$writerStatus = New-UiLabel -Parent $writerPage -Text "" -X 26 -Y 124 -Width 650 -Height 54 -Size 9 -Style ([System.Drawing.FontStyle]::Bold) -Color $colors.Header

$openWriter = New-Object System.Windows.Forms.Button
$openWriter.Text = "打开猫栈 Writer..."
$openWriter.Location = New-Object System.Drawing.Point(26, 196)
$openWriter.Size = New-Object System.Drawing.Size(190, 42)
$openWriter.Font = New-UiFont -Size 9 -Style ([System.Drawing.FontStyle]::Bold)
$openWriter.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$openWriter.FlatAppearance.BorderSize = 0
$openWriter.BackColor = $colors.Accent
$openWriter.ForeColor = $colors.Text
$writerPage.Controls.Add($openWriter)

[void](New-UiLabel -Parent $writerPage -Text "首次使用时由你主动下载约 1.04 GiB 的 Qwen2.5 1.5B 模型。下载完成后可完全离线推理；模型和原文不会上传到猫栈服务器。" -X 26 -Y 262 -Width 650 -Height 64 -Size 9 -Color $colors.Muted)
[void](New-UiLabel -Parent $writerPage -Text "严格隐私模式会强制关闭 Writer；短句自动补全仍保持关闭。" -X 26 -Y 340 -Width 650 -Height 34 -Size 9 -Color $colors.Danger)

function Refresh-WriterSummary {
    $installed = (Test-Path $writerModelPath) -and ((Get-Item $writerModelPath).Length -eq $writerModelSize)
    $writerStatus.Text = if ($installed) {
        "模型状态：已安装。打开 Writer 后可明确启用并使用改写、翻译。"
    } else {
        "模型状态：尚未安装。Writer 默认关闭，不影响普通输入。"
    }
}

$openWriter.Add_Click({
    if (-not (Test-Path $writerScriptPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "没有找到 Writer 管理程序，请重新安装猫栈拼音。",
            "猫栈拼音",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File `"$writerScriptPath`""
})

Refresh-WriterSummary

$aboutPage = New-Object System.Windows.Forms.TabPage
$aboutPage.Text = "关于"
$aboutPage.BackColor = $colors.White
$tabs.TabPages.Add($aboutPage)

if (Test-Path $logoPath) {
    $aboutIcon = New-Object System.Windows.Forms.PictureBox
    $aboutIcon.Location = New-Object System.Drawing.Point(28, 28)
    $aboutIcon.Size = New-Object System.Drawing.Size(76, 76)
    $aboutIcon.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $aboutIcon.Image = [System.Drawing.Image]::FromFile($logoPath)
    $aboutPage.Controls.Add($aboutIcon)
}

[void](New-UiLabel -Parent $aboutPage -Text "猫栈拼音" -X 126 -Y 30 -Width 280 -Height 34 -Size 17 -Style ([System.Drawing.FontStyle]::Bold))
[void](New-UiLabel -Parent $aboutPage -Text "版本 $appVersion" -X 128 -Y 69 -Width 240 -Height 24 -Size 9 -Style ([System.Drawing.FontStyle]::Bold) -Color $colors.Header)
[void](New-UiLabel -Parent $aboutPage -Text "本地输入 · 无账号 · 默认不联网" -X 128 -Y 96 -Width 360 -Height 24 -Size 8 -Color $colors.Muted)

Add-Separator -Parent $aboutPage -Y 136
[void](New-UiLabel -Parent $aboutPage -Text "本版更新" -X 24 -Y 158 -Width 180 -Height 28 -Size 11 -Style ([System.Drawing.FontStyle]::Bold))
[void](New-UiLabel -Parent $aboutPage -Text "1. 稳定空格默认候选：AI Lite 只调整后续候选，不再移动首选词。" -X 28 -Y 194 -Width 650 -Height 30 -Size 9)
[void](New-UiLabel -Parent $aboutPage -Text "2. 新增可选宽容拼音，支持 zh/z、ch/c、sh/s、n/l 和前后鼻音等常见模糊音。" -X 28 -Y 232 -Width 650 -Height 30 -Size 9)
[void](New-UiLabel -Parent $aboutPage -Text "3. 用户学习改为第三次确认后生效，并加入滞回边界，减少候选随衰减来回跳动。" -X 28 -Y 270 -Width 650 -Height 30 -Size 9)
[void](New-UiLabel -Parent $aboutPage -Text "4. 统一盲打交互；仅显示预测词时数字会直接输入，例如「你好2」不会被吞掉。" -X 28 -Y 308 -Width 650 -Height 30 -Size 9)
[void](New-UiLabel -Parent $aboutPage -Text "5. 修复含空格用户路径下的白霜导入与设置文件打开，并改善下载兼容性和错误提示。" -X 28 -Y 346 -Width 650 -Height 30 -Size 9)

$footerLine = New-Object System.Windows.Forms.Panel
$footerLine.Location = New-Object System.Drawing.Point(0, 558)
$footerLine.Size = New-Object System.Drawing.Size(780, 1)
$footerLine.BackColor = $colors.Border
$form.Controls.Add($footerLine)

$statusLabel = New-UiLabel -Parent $form -Text "设置保存在本机" -X 24 -Y 578 -Width 360 -Height 24 -Size 8 -Color $colors.Muted

$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = "关闭"
$cancel.Location = New-Object System.Drawing.Point(524, 574)
$cancel.Size = New-Object System.Drawing.Size(100, 34)
$cancel.Font = New-UiFont -Size 9
$cancel.Add_Click({ $form.Close() })
$form.Controls.Add($cancel)

$save = New-Object System.Windows.Forms.Button
$save.Text = "保存设置"
$save.Location = New-Object System.Drawing.Point(636, 574)
$save.Size = New-Object System.Drawing.Size(120, 34)
$save.Font = New-UiFont -Size 9 -Style ([System.Drawing.FontStyle]::Bold)
$save.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$save.FlatAppearance.BorderSize = 0
$save.BackColor = $colors.Header
$save.ForeColor = $colors.White
$form.AcceptButton = $save
$form.Controls.Add($save)

function Update-PrivacyControls {
    if ($privacy.Checked) {
        $learning.Checked = $false
        $learning.Enabled = $false
    } else {
        $learning.Enabled = $true
    }
}

$privacy.Add_CheckedChanged({ Update-PrivacyControls })
Update-PrivacyControls

$save.Add_Click({
    # Always merge form values into the latest on-disk snapshot. Other page actions
    # (including White Frost enable/disable) can update settings while this window is open.
    $currentSettings = Read-Settings
    $currentSettings.default_mode = if ($defaultMode.SelectedIndex -eq 1) { "English" } else { "Chinese" }
    $currentSettings.toggle_key = if ($toggleKey.SelectedIndex -eq 1) { "CtrlSpace" } else { "Shift" }
    $currentSettings.enable_prediction = $prediction.Checked
    $currentSettings.candidate_page_size = [decimal]::ToInt32($candidatePageSize.Value)
    $currentSettings.candidate_font_size = [decimal]::ToInt32($candidateFontSize.Value)
    $currentSettings.theme = switch ($theme.SelectedIndex) {
        1 { "light" }
        2 { "dark" }
        default { "system" }
    }
    $currentSettings.strict_privacy_mode = $privacy.Checked
    $currentSettings.enable_user_learning = if ($privacy.Checked) { $false } else { $learning.Checked }
    if ($null -eq $currentSettings.PSObject.Properties["ai"] -or $null -eq $currentSettings.ai) {
        Set-JsonProperty $currentSettings "ai" ([pscustomobject]@{})
    }
    Set-JsonProperty $currentSettings.ai "enable_pinyin_correction" ([bool]$pinyinCorrection.Checked)
    if ([bool]$tolerantPinyin.Checked -ne [bool]$initialTolerantPinyinEnabled) {
        if ($null -eq $currentSettings.PSObject.Properties["fuzzy_pinyin"] -or
            $null -eq $currentSettings.fuzzy_pinyin) {
            Set-JsonProperty $currentSettings "fuzzy_pinyin" ([pscustomobject]@{})
        }
        foreach ($key in $fuzzyPinyinKeys) {
            Set-JsonProperty $currentSettings.fuzzy_pinyin $key ([bool]$tolerantPinyin.Checked)
        }
    }
    Write-Settings $currentSettings
    $script:settings = $currentSettings
    $script:initialTolerantPinyinEnabled = [bool]$tolerantPinyin.Checked
    $statusLabel.Text = "设置已保存，重新切换一次输入法后生效"
    $statusLabel.ForeColor = $colors.Success
})

$clear.Add_Click({
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "确定清空本机用户词库吗？此操作无法撤销。",
        "清空用户词库",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    $ok = Run-SettingsTool @("clear-user-lexicon", "--settings", $settingsPath)
    $statusLabel.Text = if ($ok) { "用户词库已清空" } else { "无法清空用户词库" }
    $statusLabel.ForeColor = if ($ok) { $colors.Success } else { $colors.Danger }
})

$export.Add_Click({
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.FileName = "private-pinyin-user-lexicon.tsv"
    $dialog.Filter = "TSV 文件 (*.tsv)|*.tsv|所有文件 (*.*)|*.*"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $ok = Run-SettingsTool @("export-user-lexicon", "--settings", $settingsPath, "--output", $dialog.FileName)
        $statusLabel.Text = if ($ok) { "用户词库已导出" } else { "无法导出用户词库" }
        $statusLabel.ForeColor = if ($ok) { $colors.Success } else { $colors.Danger }
    }
})

$importRime.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Multiselect = $true
    $dialog.Filter = "Rime 词典 (*.yaml;*.yml;*.dict)|*.yaml;*.yml;*.dict|所有文件 (*.*)|*.*"
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    foreach ($fileName in $dialog.FileNames) {
        $ok = Run-SettingsTool @("import-rime-lexicon", "--settings", $settingsPath, "--input", $fileName)
        if (-not $ok) {
            $statusLabel.Text = "无法导入 Rime 词库"
            $statusLabel.ForeColor = $colors.Danger
            return
        }
    }
    $statusLabel.Text = "Rime 词库已导入，重新切换一次输入法后生效"
    $statusLabel.ForeColor = $colors.Success
})

$clearImported.Add_Click({
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "确定清空手动导入的词库吗？内置词库和用户学习数据不会受影响。",
        "清空导入词库",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    $ok = Run-SettingsTool @("clear-imported-lexicon", "--settings", $settingsPath)
    $statusLabel.Text = if ($ok) { "导入词库已清空，重新切换一次输入法后生效" } else { "无法清空导入词库" }
    $statusLabel.ForeColor = if ($ok) { $colors.Success } else { $colors.Danger }
})

$openJson.Add_Click({
    Start-Process -FilePath "notepad.exe" -ArgumentList "`"$settingsPath`""
})

if ($PreviewPath) {
    $tabs.SelectedIndex = switch ($PreviewTab) {
        "privacy" { 1 }
        "lexicon" { 2 }
        "writer" { 3 }
        "about" { 4 }
        default { 0 }
    }
    $previewDirectory = Split-Path -Parent $PreviewPath
    if ($previewDirectory -and -not (Test-Path $previewDirectory)) {
        New-Item -ItemType Directory -Force -Path $previewDirectory | Out-Null
    }

    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $bitmap = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
    $bounds = New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)
    $form.DrawToBitmap($bitmap, $bounds)
    $bitmap.Save($PreviewPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    $form.Close()
    exit 0
}

[void]$form.ShowDialog()
