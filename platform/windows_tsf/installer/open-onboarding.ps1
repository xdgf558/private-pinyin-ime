param(
    [switch]$StatusOnly,
    [switch]$AddInputMethod,
    [string]$PreviewPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

$textServiceClsid = "{6A7D5301-42D7-41FB-9954-4F98A63F6210}"
$profileGuid = "{B6332FC3-833D-4F7E-A112-5895851CDA34}"
$inputMethodTip = "0804:$textServiceClsid$profileGuid"
$chineseLanguageTags = @("zh-Hans-CN", "zh-CN")

function Test-InputMethodTip {
    param([AllowNull()]$Tips)

    foreach ($tip in $Tips) {
        if ([string]::Equals([string]$tip, $inputMethodTip, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-PrivatePinyinState {
    $registrationPaths = @(
        "Registry::HKEY_CURRENT_USER\Software\Classes\CLSID\$textServiceClsid\InprocServer32",
        "Registry::HKEY_CLASSES_ROOT\CLSID\$textServiceClsid\InprocServer32"
    )
    $registered = $false
    $registeredServerPath = $null
    foreach ($registrationPath in $registrationPaths) {
        if (-not (Test-Path $registrationPath)) {
            continue
        }

        $serverPath = (Get-Item $registrationPath).GetValue("")
        if ($serverPath -and (Test-Path $serverPath)) {
            $registered = $true
            $registeredServerPath = $serverPath
            break
        }
    }
    $languageToolsAvailable = $null -ne (Get-Command Get-WinUserLanguageList -ErrorAction SilentlyContinue) -and
        $null -ne (Get-Command Set-WinUserLanguageList -ErrorAction SilentlyContinue)
    $enabled = $false
    $hasChineseLanguage = $false

    if ($languageToolsAvailable) {
        $languageList = Get-WinUserLanguageList
        foreach ($language in $languageList) {
            if ($chineseLanguageTags -contains [string]$language.LanguageTag) {
                $hasChineseLanguage = $true
                if (Test-InputMethodTip -Tips $language.InputMethodTips) {
                    $enabled = $true
                }
            }
        }
    }

    [pscustomobject]@{
        Registered = $registered
        Enabled = $enabled
        HasChineseLanguage = $hasChineseLanguage
        LanguageToolsAvailable = $languageToolsAvailable
        InputMethodTip = $inputMethodTip
        RegisteredServerPath = $registeredServerPath
    }
}

function Add-PrivatePinyinInputMethod {
    $state = Get-PrivatePinyinState
    if (-not $state.Registered) {
        throw "没有检测到猫栈拼音的 Windows 组件，请重新运行安装程序。"
    }
    if (-not $state.LanguageToolsAvailable) {
        throw "当前 Windows 系统不支持自动添加，请改用「打开语言设置」。"
    }
    if ($state.Enabled) {
        return $state
    }

    $languageList = Get-WinUserLanguageList
    $chineseLanguage = $null
    foreach ($language in $languageList) {
        if ($chineseLanguageTags -contains [string]$language.LanguageTag) {
            $chineseLanguage = $language
            break
        }
    }

    if (-not $chineseLanguage) {
        $languageList.Add("zh-Hans-CN")
        foreach ($language in $languageList) {
            if ($chineseLanguageTags -contains [string]$language.LanguageTag) {
                $chineseLanguage = $language
                break
            }
        }
    }

    if (-not $chineseLanguage) {
        throw "无法创建简体中文语言项，请先在 Windows 设置中添加简体中文。"
    }

    if (-not (Test-InputMethodTip -Tips $chineseLanguage.InputMethodTips)) {
        [void]$chineseLanguage.InputMethodTips.Add($inputMethodTip)
    }
    Set-WinUserLanguageList -LanguageList $languageList -Force

    $updatedState = Get-PrivatePinyinState
    if (-not $updatedState.Enabled) {
        throw "Windows 没有确认输入法已添加，请打开语言设置手动添加。"
    }
    return $updatedState
}

if ($StatusOnly) {
    Get-PrivatePinyinState | ConvertTo-Json -Compress
    exit 0
}

if ($AddInputMethod) {
    Add-PrivatePinyinInputMethod | ConvertTo-Json -Compress
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$installDir = $PSScriptRoot
$settingsScript = Join-Path $installDir "open-settings.ps1"
$iconPath = Join-Path $installDir "PrivatePinyinInstaller.ico"

$colors = @{
    Header = [System.Drawing.Color]::FromArgb(19, 72, 74)
    Accent = [System.Drawing.Color]::FromArgb(244, 181, 62)
    Text = [System.Drawing.Color]::FromArgb(32, 39, 42)
    Muted = [System.Drawing.Color]::FromArgb(94, 104, 108)
    Border = [System.Drawing.Color]::FromArgb(222, 226, 226)
    Surface = [System.Drawing.Color]::FromArgb(246, 248, 248)
    Success = [System.Drawing.Color]::FromArgb(30, 122, 76)
    Warning = [System.Drawing.Color]::FromArgb(174, 102, 13)
    White = [System.Drawing.Color]::White
}

function New-GuideFont {
    param(
        [float]$Size,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )

    New-Object System.Drawing.Font -ArgumentList @("Microsoft YaHei UI", $Size, $Style, [System.Drawing.GraphicsUnit]::Point)
}

function New-GuideLabel {
    param(
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
    $label.Font = New-GuideFont -Size $Size -Style $Style
    $label.ForeColor = $Color
    $label.BackColor = [System.Drawing.Color]::Transparent
    return $label
}

function New-StepNumber {
    param([string]$Number, [int]$Y)

    $label = New-GuideLabel -Text $Number -X 34 -Y $Y -Width 30 -Height 30 -Size 10 -Style ([System.Drawing.FontStyle]::Bold)
    $label.BackColor = $colors.Accent
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    return $label
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "猫栈拼音安装引导"
$form.StartPosition = "CenterScreen"
$form.ClientSize = New-Object System.Drawing.Size(760, 548)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.BackColor = $colors.White

if (Test-Path $iconPath) {
    $form.Icon = New-Object System.Drawing.Icon($iconPath)
}

$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size(760, 98)
$header.BackColor = $colors.Header
$form.Controls.Add($header)

$brandMark = New-Object System.Windows.Forms.Panel
$brandMark.Location = New-Object System.Drawing.Point(34, 23)
$brandMark.Size = New-Object System.Drawing.Size(52, 52)
$brandMark.BackColor = $colors.Accent
$header.Controls.Add($brandMark)

$brandGlyph = New-GuideLabel -Text "拼" -X 0 -Y 3 -Width 52 -Height 46 -Size 21 -Style ([System.Drawing.FontStyle]::Bold) -Color $colors.Header
$brandGlyph.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$brandMark.Controls.Add($brandGlyph)

$brand = New-GuideLabel -Text "猫栈拼音" -X 104 -Y 21 -Width 400 -Height 34 -Size 19 -Style ([System.Drawing.FontStyle]::Bold) -Color $colors.White
$header.Controls.Add($brand)
$headerSubtitle = New-GuideLabel -Text "Windows 输入设置" -X 106 -Y 57 -Width 300 -Height 22 -Size 9 -Color ([System.Drawing.Color]::FromArgb(218, 233, 233))
$header.Controls.Add($headerSubtitle)

$title = New-GuideLabel -Text "再完成一步，就可以开始输入" -X 34 -Y 122 -Width 680 -Height 32 -Size 15 -Style ([System.Drawing.FontStyle]::Bold)
$form.Controls.Add($title)
$intro = New-GuideLabel -Text "将输入法添加到当前账户的中文键盘列表。你的默认输入法和其他键盘不会改变。" -X 34 -Y 158 -Width 680 -Height 24 -Size 9 -Color $colors.Muted
$form.Controls.Add($intro)

$railTop = New-Object System.Windows.Forms.Panel
$railTop.Location = New-Object System.Drawing.Point(48, 218)
$railTop.Size = New-Object System.Drawing.Size(2, 54)
$railTop.BackColor = $colors.Border
$form.Controls.Add($railTop)
$railBottom = New-Object System.Windows.Forms.Panel
$railBottom.Location = New-Object System.Drawing.Point(48, 305)
$railBottom.Size = New-Object System.Drawing.Size(2, 54)
$railBottom.BackColor = $colors.Border
$form.Controls.Add($railBottom)

$form.Controls.Add((New-StepNumber -Number "1" -Y 190))
$form.Controls.Add((New-StepNumber -Number "2" -Y 276))
$form.Controls.Add((New-StepNumber -Number "3" -Y 363))

$step1Title = New-GuideLabel -Text "安装输入法组件" -X 82 -Y 188 -Width 350 -Height 25 -Size 10 -Style ([System.Drawing.FontStyle]::Bold)
$form.Controls.Add($step1Title)
$step1Status = New-GuideLabel -Text "正在检测..." -X 82 -Y 216 -Width 520 -Height 23 -Size 9 -Color $colors.Muted
$form.Controls.Add($step1Status)

$step2Title = New-GuideLabel -Text "添加到输入法列表" -X 82 -Y 274 -Width 350 -Height 25 -Size 10 -Style ([System.Drawing.FontStyle]::Bold)
$form.Controls.Add($step2Title)
$step2Status = New-GuideLabel -Text "正在检测..." -X 82 -Y 302 -Width 430 -Height 42 -Size 9 -Color $colors.Muted
$form.Controls.Add($step2Status)

$addButton = New-Object System.Windows.Forms.Button
$addButton.Text = "添加输入法"
$addButton.Location = New-Object System.Drawing.Point(568, 286)
$addButton.Size = New-Object System.Drawing.Size(150, 38)
$addButton.Font = New-GuideFont -Size 9 -Style ([System.Drawing.FontStyle]::Bold)
$addButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$addButton.FlatAppearance.BorderSize = 0
$addButton.BackColor = $colors.Header
$addButton.ForeColor = $colors.White
$addButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($addButton)

$step3Title = New-GuideLabel -Text "切换并试用" -X 82 -Y 361 -Width 350 -Height 25 -Size 10 -Style ([System.Drawing.FontStyle]::Bold)
$form.Controls.Add($step3Title)
$step3Status = New-GuideLabel -Text "按 Win + 空格选择「猫栈拼音」，在记事本中输入 nihao。" -X 82 -Y 389 -Width 470 -Height 42 -Size 9 -Color $colors.Muted
$form.Controls.Add($step3Status)

$testButton = New-Object System.Windows.Forms.Button
$testButton.Text = "打开记事本试用"
$testButton.Location = New-Object System.Drawing.Point(568, 374)
$testButton.Size = New-Object System.Drawing.Size(150, 38)
$testButton.Font = New-GuideFont -Size 9
$testButton.Enabled = $false
$testButton.Add_Click({ Start-Process "notepad.exe" })
$form.Controls.Add($testButton)

$footerLine = New-Object System.Windows.Forms.Panel
$footerLine.Location = New-Object System.Drawing.Point(0, 457)
$footerLine.Size = New-Object System.Drawing.Size(760, 1)
$footerLine.BackColor = $colors.Border
$form.Controls.Add($footerLine)

$privacy = New-GuideLabel -Text "本地输入  |  无账号  |  默认不联网" -X 34 -Y 474 -Width 285 -Height 24 -Size 8 -Color $colors.Muted
$form.Controls.Add($privacy)

$languageSettingsButton = New-Object System.Windows.Forms.Button
$languageSettingsButton.Text = "语言设置"
$languageSettingsButton.Location = New-Object System.Drawing.Point(354, 474)
$languageSettingsButton.Size = New-Object System.Drawing.Size(105, 34)
$languageSettingsButton.Add_Click({ Start-Process "ms-settings:regionlanguage" })
$form.Controls.Add($languageSettingsButton)

$preferencesButton = New-Object System.Windows.Forms.Button
$preferencesButton.Text = "偏好设置"
$preferencesButton.Location = New-Object System.Drawing.Point(470, 474)
$preferencesButton.Size = New-Object System.Drawing.Size(105, 34)
$preferencesButton.Add_Click({
    if (Test-Path $settingsScript) {
        Start-Process powershell.exe -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            "`"$settingsScript`""
        ) -WindowStyle Hidden
    }
})
$form.Controls.Add($preferencesButton)

$doneButton = New-Object System.Windows.Forms.Button
$doneButton.Text = "完成"
$doneButton.Location = New-Object System.Drawing.Point(586, 474)
$doneButton.Size = New-Object System.Drawing.Size(132, 34)
$doneButton.Font = New-GuideFont -Size 9 -Style ([System.Drawing.FontStyle]::Bold)
$doneButton.Add_Click({ $form.Close() })
$form.AcceptButton = $doneButton
$form.Controls.Add($doneButton)

function Update-GuideState {
    $state = Get-PrivatePinyinState

    if ($state.Registered) {
        $step1Status.Text = "已完成：Windows 输入法组件已注册。"
        $step1Status.ForeColor = $colors.Success
    } else {
        $step1Status.Text = "未检测到组件，请关闭此窗口并重新运行安装程序。"
        $step1Status.ForeColor = $colors.Warning
    }

    if ($state.Enabled) {
        $step2Status.Text = "已完成：猫栈拼音已在当前账户的输入法列表中。"
        $step2Status.ForeColor = $colors.Success
        $addButton.Text = "已添加"
        $addButton.Enabled = $false
        $addButton.BackColor = [System.Drawing.Color]::FromArgb(214, 222, 220)
        $addButton.ForeColor = $colors.Muted
        $testButton.Enabled = $true
    } elseif (-not $state.Registered) {
        $step2Status.Text = "安装组件修复后，才能添加到输入法列表。"
        $step2Status.ForeColor = $colors.Warning
        $addButton.Enabled = $false
        $testButton.Enabled = $false
    } elseif (-not $state.LanguageToolsAvailable) {
        $step2Status.Text = "请点击下方「语言设置」，在中文键盘中手动添加。"
        $step2Status.ForeColor = $colors.Warning
        $addButton.Enabled = $false
        $testButton.Enabled = $false
    } else {
        $step2Status.Text = "点击右侧按钮，一键添加到当前账户。"
        $step2Status.ForeColor = $colors.Muted
        $addButton.Text = "添加输入法"
        $addButton.Enabled = $true
        $addButton.BackColor = $colors.Header
        $addButton.ForeColor = $colors.White
        $testButton.Enabled = $false
    }

    return $state
}

$addButton.Add_Click({
    $addButton.Enabled = $false
    $addButton.Text = "正在添加..."
    $form.Refresh()

    try {
        [void](Add-PrivatePinyinInputMethod)
        [void](Update-GuideState)
        [System.Windows.Forms.MessageBox]::Show(
            "猫栈拼音已添加。现在可以按 Win + 空格切换并开始输入。",
            "添加完成",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } catch {
        [void](Update-GuideState)
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "无法添加输入法",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
})

[void](Update-GuideState)

if ($PreviewPath) {
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
