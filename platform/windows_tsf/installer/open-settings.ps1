param(
    [string]$SettingsTool = (Join-Path $PSScriptRoot "private-pinyin-settings.exe"),
    [string]$PreviewPath = "",
    [ValidateSet("general", "privacy", "about")][string]$PreviewTab = "general"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$dataDir = Join-Path $env:LOCALAPPDATA "PrivatePinyin"
$settingsPath = Join-Path $dataDir "settings.json"
$userLexiconPath = Join-Path $dataDir "user_lexicon.sqlite"
$iconPath = Join-Path $PSScriptRoot "PrivatePinyinInstaller.ico"
$logoPath = Join-Path $PSScriptRoot "PrivatePinyinLogo.png"

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
    return $settings
}

function Ensure-SettingsFile {
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
    if (-not (Test-Path $settingsPath)) {
        $settings = Get-DefaultSettings
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

function Run-SettingsTool($arguments) {
    if (-not (Test-Path $SettingsTool)) {
        [System.Windows.Forms.MessageBox]::Show(
            "没有找到词库工具：$SettingsTool",
            "猫栈拼音",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $false
    }

    $process = Start-Process -FilePath $SettingsTool -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    return $process.ExitCode -eq 0
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

[void](New-UiLabel -Parent $generalPage -Text "每页候选数量" -X 24 -Y 286 -Width 170 -Height 26 -Size 9)
$candidatePageSize = New-Object System.Windows.Forms.NumericUpDown
$candidatePageSize.Location = New-Object System.Drawing.Point(235, 281)
$candidatePageSize.Size = New-Object System.Drawing.Size(90, 28)
$candidatePageSize.Minimum = 3
$candidatePageSize.Maximum = 9
$candidatePageSize.Value = [decimal][int]$settings.candidate_page_size
$generalPage.Controls.Add($candidatePageSize)

[void](New-UiLabel -Parent $generalPage -Text "候选字号" -X 24 -Y 334 -Width 170 -Height 26 -Size 9)
$candidateFontSize = New-Object System.Windows.Forms.NumericUpDown
$candidateFontSize.Location = New-Object System.Drawing.Point(235, 329)
$candidateFontSize.Size = New-Object System.Drawing.Size(90, 28)
$candidateFontSize.Minimum = 10
$candidateFontSize.Maximum = 24
$candidateFontSize.Value = [decimal][int]$settings.candidate_font_size
$generalPage.Controls.Add($candidateFontSize)

[void](New-UiLabel -Parent $generalPage -Text "界面主题" -X 385 -Y 286 -Width 120 -Height 26 -Size 9)
$theme = New-Object System.Windows.Forms.ComboBox
$theme.Location = New-Object System.Drawing.Point(505, 281)
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
$tabs.TabPages.Add($privacyPage)

$privacy = New-Object System.Windows.Forms.CheckBox
$privacy.Text = "严格隐私模式"
$privacy.Location = New-Object System.Drawing.Point(24, 28)
$privacy.Size = New-Object System.Drawing.Size(220, 28)
$privacy.Font = New-UiFont -Size 10 -Style ([System.Drawing.FontStyle]::Bold)
$privacy.Checked = [bool]$settings.strict_privacy_mode
$privacyPage.Controls.Add($privacy)
[void](New-UiLabel -Parent $privacyPage -Text "开启后停止记录新的用户词频，现有本地词库不会上传。" -X 46 -Y 59 -Width 600 -Height 24 -Size 8 -Color $colors.Muted)

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
[void](New-UiLabel -Parent $aboutPage -Text "1. 新增 x86 输入法组件，支持 QQ 等 32 位 Windows 应用。" -X 28 -Y 202 -Width 650 -Height 28 -Size 9)
[void](New-UiLabel -Parent $aboutPage -Text "2. 安装器会同时注册 x64 与 x86 TSF，并在引导中分别检测。" -X 28 -Y 244 -Width 650 -Height 28 -Size 9)
[void](New-UiLabel -Parent $aboutPage -Text "3. 继续提供本机 trigram 联想、30 天衰减和容量控制。" -X 28 -Y 286 -Width 650 -Height 28 -Size 9)

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
    $settings.default_mode = if ($defaultMode.SelectedIndex -eq 1) { "English" } else { "Chinese" }
    $settings.toggle_key = if ($toggleKey.SelectedIndex -eq 1) { "CtrlSpace" } else { "Shift" }
    $settings.enable_prediction = $prediction.Checked
    $settings.candidate_page_size = [decimal]::ToInt32($candidatePageSize.Value)
    $settings.candidate_font_size = [decimal]::ToInt32($candidateFontSize.Value)
    $settings.theme = switch ($theme.SelectedIndex) {
        1 { "light" }
        2 { "dark" }
        default { "system" }
    }
    $settings.strict_privacy_mode = $privacy.Checked
    $settings.enable_user_learning = if ($privacy.Checked) { $false } else { $learning.Checked }
    Write-Settings $settings
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

$openJson.Add_Click({ Start-Process notepad.exe $settingsPath })

if ($PreviewPath) {
    $tabs.SelectedIndex = switch ($PreviewTab) {
        "privacy" { 1 }
        "about" { 2 }
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
