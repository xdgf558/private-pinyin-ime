param(
    [string]$SettingsTool = (Join-Path $PSScriptRoot "private-pinyin-settings.exe")
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$dataDir = Join-Path $env:LOCALAPPDATA "PrivatePinyin"
$settingsPath = Join-Path $dataDir "settings.json"
$userLexiconPath = Join-Path $dataDir "user_lexicon.sqlite"

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

    throw "Missing default_settings.json template."
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
            "Missing settings tool: $SettingsTool",
            "猫栈拼音",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $false
    }

    $process = Start-Process -FilePath $SettingsTool -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    return $process.ExitCode -eq 0
}

Ensure-SettingsFile
$settings = Read-Settings

$form = New-Object System.Windows.Forms.Form
$form.Text = "猫栈拼音偏好设置"
$form.StartPosition = "CenterScreen"
$form.Width = 420
$form.Height = 250
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$privacy = New-Object System.Windows.Forms.CheckBox
$privacy.Text = "严格隐私模式"
$privacy.Left = 24
$privacy.Top = 24
$privacy.Width = 220
$privacy.Checked = [bool]$settings.strict_privacy_mode
$form.Controls.Add($privacy)

$learning = New-Object System.Windows.Forms.CheckBox
$learning.Text = "启用用户学习"
$learning.Left = 24
$learning.Top = 58
$learning.Width = 220
$learning.Checked = [bool]$settings.enable_user_learning
$form.Controls.Add($learning)

$prediction = New-Object System.Windows.Forms.CheckBox
$prediction.Text = "显示预测候选"
$prediction.Left = 24
$prediction.Top = 92
$prediction.Width = 220
$prediction.Checked = [bool]$settings.enable_prediction
$form.Controls.Add($prediction)

$save = New-Object System.Windows.Forms.Button
$save.Text = "保存"
$save.Left = 270
$save.Top = 22
$save.Width = 110
$save.Add_Click({
    $settings.strict_privacy_mode = $privacy.Checked
    $settings.enable_user_learning = if ($privacy.Checked) { $false } else { $learning.Checked }
    $settings.enable_prediction = $prediction.Checked
    Write-Settings $settings
    [System.Windows.Forms.MessageBox]::Show("设置已保存。请重新切换一次输入法以载入新设置。", "猫栈拼音") | Out-Null
})
$form.Controls.Add($save)

$clear = New-Object System.Windows.Forms.Button
$clear.Text = "清空词库"
$clear.Left = 270
$clear.Top = 62
$clear.Width = 110
$clear.Add_Click({
    $ok = Run-SettingsTool @("clear-user-lexicon", "--settings", $settingsPath)
    $message = if ($ok) { "用户词库已清空。" } else { "无法清空用户词库。" }
    [System.Windows.Forms.MessageBox]::Show($message, "猫栈拼音") | Out-Null
})
$form.Controls.Add($clear)

$export = New-Object System.Windows.Forms.Button
$export.Text = "导出..."
$export.Left = 270
$export.Top = 102
$export.Width = 110
$export.Add_Click({
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.FileName = "private-pinyin-user-lexicon.tsv"
    $dialog.Filter = "TSV files (*.tsv)|*.tsv|All files (*.*)|*.*"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $ok = Run-SettingsTool @("export-user-lexicon", "--settings", $settingsPath, "--output", $dialog.FileName)
        $message = if ($ok) { "用户词库已导出。" } else { "无法导出用户词库。" }
        [System.Windows.Forms.MessageBox]::Show($message, "猫栈拼音") | Out-Null
    }
})
$form.Controls.Add($export)

$openJson = New-Object System.Windows.Forms.Button
$openJson.Text = "打开 JSON"
$openJson.Left = 270
$openJson.Top = 142
$openJson.Width = 110
$openJson.Add_Click({
    Start-Process notepad.exe $settingsPath
})
$form.Controls.Add($openJson)

[void]$form.ShowDialog()
