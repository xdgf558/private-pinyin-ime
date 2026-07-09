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
$form.Text = "PrivatePinyin IME Setup"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(680, 430)
$form.MinimumSize = New-Object System.Drawing.Size(680, 430)

$title = New-Label `
    -Text "PrivatePinyin IME is installed" `
    -X 28 `
    -Y 24 `
    -Width 600 `
    -Height 32 `
    -Size 16 `
    -Bold
$form.Controls.Add($title)

$summary = New-Label `
    -Text "Finish setup in Windows language settings, then switch input methods with Win+Space." `
    -X 30 `
    -Y 62 `
    -Width 600 `
    -Height 26 `
    -Size 10
$form.Controls.Add($summary)

$steps = @(
    "1. Open Windows Settings > Time & language > Language & region.",
    "2. Add Chinese if needed, then enable the PrivatePinyin IME input method.",
    "3. In Notepad, press Win+Space, choose PrivatePinyin IME, and type nihao.",
    "4. If the input method does not appear immediately, sign out and sign back in once."
)

$y = 112
foreach ($step in $steps) {
    $label = New-Label -Text $step -X 44 -Y $y -Width 590 -Height 28 -Size 10
    $form.Controls.Add($label)
    $y += 38
}

$privacy = New-Label `
    -Text "Privacy note: settings, learning data, and user lexicon files stay under your local AppData folder." `
    -X 30 `
    -Y 284 `
    -Width 600 `
    -Height 28 `
    -Size 9
$privacy.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$form.Controls.Add($privacy)

$openLanguageSettingsButton = New-Object System.Windows.Forms.Button
$openLanguageSettingsButton.Text = "Open language settings"
$openLanguageSettingsButton.Location = New-Object System.Drawing.Point(30, 330)
$openLanguageSettingsButton.Size = New-Object System.Drawing.Size(190, 34)
$openLanguageSettingsButton.Add_Click({
    Start-Process "ms-settings:regionlanguage"
})
$form.Controls.Add($openLanguageSettingsButton)

$openPreferencesButton = New-Object System.Windows.Forms.Button
$openPreferencesButton.Text = "Open preferences"
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
$closeButton.Text = "Close"
$closeButton.Location = New-Object System.Drawing.Point(520, 330)
$closeButton.Size = New-Object System.Drawing.Size(110, 34)
$closeButton.Add_Click({ $form.Close() })
$form.Controls.Add($closeButton)

[void]$form.ShowDialog()
