$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$installDir = $PSScriptRoot
$settingsScript = Join-Path $installDir "open-settings.ps1"

function New-Label {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [float]$Size = 10,
        [switch]$Bold
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, $Height)
    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $label.Font = New-Object System.Drawing.Font -ArgumentList @("Segoe UI", $Size, $style)
    $label
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "猫栈拼音安装引导"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(680, 430)
$form.MinimumSize = New-Object System.Drawing.Size(680, 430)

$title = New-Label `
    -Text "猫栈拼音已安装" `
    -X 28 `
    -Y 24 `
    -Width 600 `
    -Height 32 `
    -Size 16 `
    -Bold
$form.Controls.Add($title)

$summary = New-Label `
    -Text "请在 Windows 语言设置里启用输入法，然后用 Win+空格切换到猫栈拼音。" `
    -X 30 `
    -Y 62 `
    -Width 600 `
    -Height 26 `
    -Size 10
$form.Controls.Add($summary)

$steps = @(
    "1. 打开 Windows 设置 > 时间和语言 > 语言和区域。",
    "2. 如有需要先添加中文，然后启用「猫栈拼音」输入法。",
    "3. 打开记事本，按 Win+空格选择「猫栈拼音」，输入 nihao 试试。",
    "4. 如果输入法没有立刻出现，注销并重新登录一次。"
)

$y = 112
foreach ($step in $steps) {
    $label = New-Label -Text $step -X 44 -Y $y -Width 590 -Height 28 -Size 10
    $form.Controls.Add($label)
    $y += 38
}

$privacy = New-Label `
    -Text "隐私说明：设置、学习数据和用户词库都保存在本机 AppData 文件夹内。" `
    -X 30 `
    -Y 284 `
    -Width 600 `
    -Height 28 `
    -Size 9
$privacy.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$form.Controls.Add($privacy)

$openLanguageSettingsButton = New-Object System.Windows.Forms.Button
$openLanguageSettingsButton.Text = "打开语言设置"
$openLanguageSettingsButton.Location = New-Object System.Drawing.Point(30, 330)
$openLanguageSettingsButton.Size = New-Object System.Drawing.Size(190, 34)
$openLanguageSettingsButton.Add_Click({
    Start-Process "ms-settings:regionlanguage"
})
$form.Controls.Add($openLanguageSettingsButton)

$openPreferencesButton = New-Object System.Windows.Forms.Button
$openPreferencesButton.Text = "打开偏好设置"
$openPreferencesButton.Location = New-Object System.Drawing.Point(236, 330)
$openPreferencesButton.Size = New-Object System.Drawing.Size(160, 34)
$openPreferencesButton.Add_Click({
    if (Test-Path $settingsScript) {
        Start-Process powershell.exe -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $settingsScript
        )
    }
})
$form.Controls.Add($openPreferencesButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "关闭"
$closeButton.Location = New-Object System.Drawing.Point(520, 330)
$closeButton.Size = New-Object System.Drawing.Size(110, 34)
$closeButton.Add_Click({ $form.Close() })
$form.Controls.Add($closeButton)

[void]$form.ShowDialog()
