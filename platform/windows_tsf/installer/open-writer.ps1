param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$dataDir = Join-Path $env:LOCALAPPDATA "PrivatePinyin"
$settingsPath = Join-Path $dataDir "settings.json"
$modelId = "qwen2.5-1.5b-instruct-q4-k-m"
$modelFilename = "qwen2.5-1.5b-instruct-q4_k_m.gguf"
$modelDirectory = Join-Path (Join-Path $dataDir "WriterModels") $modelId
$modelPath = Join-Path $modelDirectory $modelFilename
$modelStagingPath = Join-Path $modelDirectory ".$modelFilename.incoming"
$modelUrl = "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/dd26da440ef0330c47919d1ecae0966d24022222/qwen2.5-1.5b-instruct-q4_k_m.gguf"
$modelSize = [int64]1117320736
$modelSha256 = "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
$helperPath = Join-Path $PSScriptRoot "PrivatePinyinAIHelper.exe"
$iconPath = Join-Path $PSScriptRoot "PrivatePinyinInstaller.ico"
$logoPath = Join-Path $PSScriptRoot "PrivatePinyinLogo.png"

function Read-Settings {
    if (-not (Test-Path $settingsPath)) {
        throw "请先打开一次猫栈拼音偏好设置。"
    }
    return Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
}

function Write-Settings($settings) {
    $temporaryPath = "$settingsPath.tmp"
    $settings | ConvertTo-Json -Depth 6 | Set-Content -Path $temporaryPath -Encoding UTF8
    Move-Item -Force -Path $temporaryPath -Destination $settingsPath
}

function Ensure-AiSettings($settings) {
    if ($null -eq $settings.PSObject.Properties["ai"]) {
        $settings | Add-Member -NotePropertyName "ai" -NotePropertyValue ([PSCustomObject]@{})
    }
    foreach ($entry in @(
        @{ Name = "enable_short_completion"; Value = $false },
        @{ Name = "enable_rewrite"; Value = $false },
        @{ Name = "enable_translation"; Value = $false }
    )) {
        if ($null -eq $settings.ai.PSObject.Properties[$entry.Name]) {
            $settings.ai | Add-Member -NotePropertyName $entry.Name -NotePropertyValue $entry.Value
        }
    }
    return $settings
}

function Test-ModelQuickly {
    if (-not (Test-Path $modelPath)) {
        return $false
    }
    return (Get-Item $modelPath).Length -eq $modelSize
}

function Write-HelperFrame {
    param(
        [System.IO.BinaryWriter]$Writer,
        [uint16]$Opcode,
        [uint64]$RequestId,
        [byte[]]$Payload
    )
    $Writer.Write([uint32]0x50504139)
    $Writer.Write([uint16]1)
    $Writer.Write($Opcode)
    $Writer.Write($RequestId)
    $Writer.Write([uint32]$Payload.Length)
    if ($Payload.Length -gt 0) {
        $Writer.Write($Payload)
    }
    $Writer.Flush()
}

function Read-ExactWithDeadline {
    param(
        [System.IO.Stream]$Stream,
        [int]$Length,
        [DateTime]$DeadlineUtc
    )
    $buffer = New-Object byte[] $Length
    $offset = 0
    while ($offset -lt $Length) {
        $remainingMilliseconds = [int][Math]::Ceiling(($DeadlineUtc - [DateTime]::UtcNow).TotalMilliseconds)
        if ($remainingMilliseconds -le 0) {
            throw "Writer Helper 响应超时。"
        }
        $task = $Stream.ReadAsync($buffer, $offset, $Length - $offset)
        if (-not $task.Wait($remainingMilliseconds)) {
            throw "Writer Helper 响应超时。"
        }
        $count = $task.Result
        if ($count -le 0) {
            throw "Writer Helper 响应不完整。"
        }
        $offset += $count
    }
    return $buffer
}

function Read-HelperFrame {
    param(
        [System.IO.Stream]$Stream,
        [DateTime]$DeadlineUtc
    )
    $header = Read-ExactWithDeadline -Stream $Stream -Length 20 -DeadlineUtc $DeadlineUtc
    $magic = [System.BitConverter]::ToUInt32($header, 0)
    $version = [System.BitConverter]::ToUInt16($header, 4)
    $opcode = [System.BitConverter]::ToUInt16($header, 6)
    $requestId = [System.BitConverter]::ToUInt64($header, 8)
    $payloadLength = [System.BitConverter]::ToUInt32($header, 16)
    if ($magic -ne [uint32]0x50504139 -or $version -ne 1 -or $payloadLength -gt 65536) {
        throw "Helper 协议校验失败。"
    }
    $payload = if ($payloadLength -gt 0) {
        Read-ExactWithDeadline -Stream $Stream -Length ([int]$payloadLength) -DeadlineUtc $DeadlineUtc
    } else {
        [byte[]]@()
    }
    if ($payload.Length -ne [int]$payloadLength) {
        throw "Helper 响应不完整。"
    }
    return [PSCustomObject]@{
        Opcode = $opcode
        RequestId = $requestId
        Payload = $payload
    }
}

function New-WriterPayload {
    param(
        [byte]$Feature,
        [uint64]$SessionId,
        [string]$Source
    )
    $localeBytes = [System.Text.Encoding]::UTF8.GetBytes("zh-CN")
    $sourceBytes = [System.Text.Encoding]::UTF8.GetBytes($Source)
    if ($sourceBytes.Length -eq 0 -or $sourceBytes.Length -gt 4096 -or $Source.Length -gt 600) {
        throw "原文需要控制在 600 个字符、4096 字节以内。"
    }
    $stream = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter($stream)
    try {
        $writer.Write([uint16]1)
        $writer.Write($Feature)
        $writer.Write([byte]1)
        $writer.Write($SessionId)
        $writer.Write([uint64]1)
        $writer.Write([uint64]0)
        $writer.Write([uint32]3000)
        $writer.Write([uint16]$localeBytes.Length)
        $writer.Write([uint32]$sourceBytes.Length)
        $writer.Write($localeBytes)
        $writer.Write($sourceBytes)
        $writer.Flush()
        return $stream.ToArray()
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Read-WriterSuggestions {
    param(
        [byte[]]$Payload,
        [byte]$ExpectedFeature,
        [uint64]$ExpectedSession
    )
    $stream = New-Object System.IO.MemoryStream(,$Payload)
    $reader = New-Object System.IO.BinaryReader($stream)
    try {
        if ($reader.ReadUInt16() -ne 1 -or $reader.ReadByte() -ne $ExpectedFeature) {
            throw "Writer 响应版本不匹配。"
        }
        $count = [int]$reader.ReadByte()
        if ($count -lt 1 -or $count -gt 3 -or $reader.ReadUInt64() -ne $ExpectedSession) {
            throw "Writer 响应身份不匹配。"
        }
        if ($reader.ReadUInt64() -ne 1 -or $reader.ReadUInt64() -ne 0) {
            throw "Writer 响应已经过期。"
        }
        $suggestions = @()
        for ($index = 0; $index -lt $count; $index++) {
            $length = [int]$reader.ReadUInt16()
            if ($length -lt 1 -or $length -gt 4096) {
                throw "Writer 响应长度无效。"
            }
            $bytes = $reader.ReadBytes($length)
            if ($bytes.Length -ne $length) {
                throw "Writer 响应不完整。"
            }
            $suggestions += [System.Text.Encoding]::UTF8.GetString($bytes)
        }
        if ($stream.Position -ne $stream.Length) {
            throw "Writer 响应含多余数据。"
        }
        return $suggestions
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Invoke-WriterHelper {
    param(
        [byte]$Feature,
        [string]$Source
    )
    if (-not (Test-Path $helperPath)) {
        throw "没有找到猫栈 Writer Helper。"
    }
    $token = New-Object byte[] 32
    $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($token)
    } finally {
        $random.Dispose()
    }
    $tokenHex = [System.BitConverter]::ToString($token).Replace("-", "").ToLowerInvariant()
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $helperPath
    $startInfo.Arguments = "--stdio --idle-timeout-ms 600000"
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables["PRIVATE_PINYIN_AI_HELPER_TOKEN"] = $tokenHex
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "无法启动猫栈 Writer Helper。"
    }
    $writer = New-Object System.IO.BinaryWriter($process.StandardInput.BaseStream)
    $responseStream = $process.StandardOutput.BaseStream
    $deadlineUtc = [DateTime]::UtcNow.AddSeconds(45)
    try {
        Write-HelperFrame -Writer $writer -Opcode 1 -RequestId 1 -Payload $token
        $auth = Read-HelperFrame -Stream $responseStream -DeadlineUtc $deadlineUtc
        if ($auth.Opcode -ne 0x8001 -or $auth.RequestId -ne 1) {
            throw "Writer Helper 认证失败。"
        }

        Write-HelperFrame -Writer $writer -Opcode 7 -RequestId 2 -Payload ([byte[]]@())
        $prepared = Read-HelperFrame -Stream $responseStream -DeadlineUtc $deadlineUtc
        if ($prepared.Opcode -ne 0x8007 -or $prepared.RequestId -ne 2) {
            throw "Writer 模型启动失败。"
        }

        # Model startup can take several seconds. Re-check consent immediately
        # before the original text crosses into the local model process.
        $currentSettings = Ensure-AiSettings (Read-Settings)
        if ([bool]$currentSettings.strict_privacy_mode -or
            -not [bool]$currentSettings.ai.enable_rewrite -or
            -not [bool]$currentSettings.ai.enable_translation) {
            throw "Writer 设置已变化，本次请求已取消。"
        }

        $sessionBytes = New-Object byte[] 8
        $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $random.GetBytes($sessionBytes)
        } finally {
            $random.Dispose()
        }
        $sessionId = [System.BitConverter]::ToUInt64($sessionBytes, 0)
        $payload = New-WriterPayload -Feature $Feature -SessionId $sessionId -Source $Source
        Write-HelperFrame -Writer $writer -Opcode 6 -RequestId 3 -Payload $payload
        $response = Read-HelperFrame -Stream $responseStream -DeadlineUtc $deadlineUtc
        if ($response.Opcode -ne 0x8006 -or $response.RequestId -ne 3) {
            throw "Writer 生成失败或超时。"
        }
        return Read-WriterSuggestions -Payload $response.Payload -ExpectedFeature $Feature -ExpectedSession $sessionId
    } finally {
        try { Write-HelperFrame -Writer $writer -Opcode 5 -RequestId 4 -Payload ([byte[]]@()) } catch {}
        $writer.Dispose()
        if (-not $process.HasExited) {
            $process.Kill()
        }
        $process.Dispose()
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
    param([float]$Size, [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular)
    return New-Object System.Drawing.Font -ArgumentList @("Microsoft YaHei UI", $Size, $Style, [System.Drawing.GraphicsUnit]::Point)
}

function Show-WriterMessage([string]$message, [System.Windows.Forms.MessageBoxIcon]$icon) {
    [System.Windows.Forms.MessageBox]::Show(
        $message,
        "猫栈 Writer",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $icon
    ) | Out-Null
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "猫栈 Writer"
$form.StartPosition = "CenterScreen"
$form.ClientSize = New-Object System.Drawing.Size(760, 660)
$form.MinimumSize = New-Object System.Drawing.Size(700, 620)
$form.BackColor = $colors.White
$form.Font = New-UiFont -Size 9
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
if (Test-Path $iconPath) {
    $form.Icon = New-Object System.Drawing.Icon($iconPath)
}

$header = New-Object System.Windows.Forms.Panel
$header.Dock = [System.Windows.Forms.DockStyle]::Top
$header.Height = 88
$header.BackColor = $colors.Header
$form.Controls.Add($header)
if (Test-Path $logoPath) {
    $headerIcon = New-Object System.Windows.Forms.PictureBox
    $headerIcon.Location = New-Object System.Drawing.Point(24, 18)
    $headerIcon.Size = New-Object System.Drawing.Size(52, 52)
    $headerIcon.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $headerIcon.Image = [System.Drawing.Image]::FromFile($logoPath)
    $header.Controls.Add($headerIcon)
}
$title = New-Object System.Windows.Forms.Label
$title.Text = "本地 Writer"
$title.Location = New-Object System.Drawing.Point(94, 17)
$title.Size = New-Object System.Drawing.Size(300, 34)
$title.Font = New-UiFont -Size 18 -Style ([System.Drawing.FontStyle]::Bold)
$title.ForeColor = $colors.White
$header.Controls.Add($title)
$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "本机改写与翻译 · 不上传原文"
$subtitle.Location = New-Object System.Drawing.Point(96, 53)
$subtitle.Size = New-Object System.Drawing.Size(420, 22)
$subtitle.Font = New-UiFont -Size 9
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(216, 231, 231)
$header.Controls.Add($subtitle)

$modelPanel = New-Object System.Windows.Forms.Panel
$modelPanel.Location = New-Object System.Drawing.Point(22, 104)
$modelPanel.Size = New-Object System.Drawing.Size(716, 94)
$modelPanel.BackColor = $colors.Surface
$form.Controls.Add($modelPanel)
$modelTitle = New-Object System.Windows.Forms.Label
$modelTitle.Text = "Writer 模型"
$modelTitle.Location = New-Object System.Drawing.Point(16, 13)
$modelTitle.Size = New-Object System.Drawing.Size(170, 24)
$modelTitle.Font = New-UiFont -Size 10 -Style ([System.Drawing.FontStyle]::Bold)
$modelPanel.Controls.Add($modelTitle)
$modelStatus = New-Object System.Windows.Forms.Label
$modelStatus.Location = New-Object System.Drawing.Point(16, 42)
$modelStatus.Size = New-Object System.Drawing.Size(440, 38)
$modelStatus.Font = New-UiFont -Size 8
$modelStatus.ForeColor = $colors.Muted
$modelPanel.Controls.Add($modelStatus)
$downloadButton = New-Object System.Windows.Forms.Button
$downloadButton.Location = New-Object System.Drawing.Point(472, 18)
$downloadButton.Size = New-Object System.Drawing.Size(126, 34)
$downloadButton.Text = "下载模型"
$downloadButton.Font = New-UiFont -Size 9 -Style ([System.Drawing.FontStyle]::Bold)
$modelPanel.Controls.Add($downloadButton)
$removeButton = New-Object System.Windows.Forms.Button
$removeButton.Location = New-Object System.Drawing.Point(606, 18)
$removeButton.Size = New-Object System.Drawing.Size(92, 34)
$removeButton.Text = "移除"
$removeButton.Font = New-UiFont -Size 9
$removeButton.ForeColor = $colors.Danger
$modelPanel.Controls.Add($removeButton)
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(472, 62)
$progress.Size = New-Object System.Drawing.Size(226, 12)
$progress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
$progress.Visible = $false
$modelPanel.Controls.Add($progress)

$enabled = New-Object System.Windows.Forms.CheckBox
$enabled.Text = "启用本地 Writer（仅处理主动提交的原文）"
$enabled.Location = New-Object System.Drawing.Point(28, 212)
$enabled.Size = New-Object System.Drawing.Size(430, 28)
$enabled.Font = New-UiFont -Size 9 -Style ([System.Drawing.FontStyle]::Bold)
$form.Controls.Add($enabled)

$feature = New-Object System.Windows.Forms.ComboBox
$feature.Location = New-Object System.Drawing.Point(28, 252)
$feature.Size = New-Object System.Drawing.Size(180, 30)
$feature.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$feature.Font = New-UiFont -Size 9
[void]$feature.Items.AddRange(@("正式改写", "礼貌改写", "精简表达", "口语改写", "中译英", "英译中"))
$feature.SelectedIndex = 0
$form.Controls.Add($feature)

$runButton = New-Object System.Windows.Forms.Button
$runButton.Text = "生成建议"
$runButton.Location = New-Object System.Drawing.Point(592, 248)
$runButton.Size = New-Object System.Drawing.Size(140, 36)
$runButton.Font = New-UiFont -Size 9 -Style ([System.Drawing.FontStyle]::Bold)
$runButton.BackColor = $colors.Header
$runButton.ForeColor = $colors.White
$runButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$runButton.FlatAppearance.BorderSize = 0
$form.Controls.Add($runButton)

$sourceLabel = New-Object System.Windows.Forms.Label
$sourceLabel.Text = "原文（最多 600 个字符）"
$sourceLabel.Location = New-Object System.Drawing.Point(28, 298)
$sourceLabel.Size = New-Object System.Drawing.Size(300, 24)
$sourceLabel.Font = New-UiFont -Size 9 -Style ([System.Drawing.FontStyle]::Bold)
$form.Controls.Add($sourceLabel)
$sourceBox = New-Object System.Windows.Forms.TextBox
$sourceBox.Location = New-Object System.Drawing.Point(28, 326)
$sourceBox.Size = New-Object System.Drawing.Size(704, 118)
$sourceBox.Multiline = $true
$sourceBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$sourceBox.Font = New-UiFont -Size 10
$form.Controls.Add($sourceBox)

$status = New-Object System.Windows.Forms.Label
$status.Text = "普通拼音输入始终不依赖 Writer。"
$status.Location = New-Object System.Drawing.Point(28, 452)
$status.Size = New-Object System.Drawing.Size(704, 28)
$status.Font = New-UiFont -Size 8
$status.ForeColor = $colors.Muted
$form.Controls.Add($status)

$resultsLabel = New-Object System.Windows.Forms.Label
$resultsLabel.Text = "建议（双击复制）"
$resultsLabel.Location = New-Object System.Drawing.Point(28, 486)
$resultsLabel.Size = New-Object System.Drawing.Size(220, 24)
$resultsLabel.Font = New-UiFont -Size 9 -Style ([System.Drawing.FontStyle]::Bold)
$form.Controls.Add($resultsLabel)
$results = New-Object System.Windows.Forms.ListBox
$results.Location = New-Object System.Drawing.Point(28, 514)
$results.Size = New-Object System.Drawing.Size(704, 112)
$results.Font = New-UiFont -Size 10
$results.HorizontalScrollbar = $true
$form.Controls.Add($results)

function Refresh-WriterState {
    try {
        $settings = Ensure-AiSettings (Read-Settings)
        $strict = [bool]$settings.strict_privacy_mode
        $enabled.Checked = [bool]$settings.ai.enable_rewrite -and [bool]$settings.ai.enable_translation
        $enabled.Enabled = -not $strict
        if ($strict) {
            $enabled.Checked = $false
            $status.Text = "严格隐私模式已强制关闭 Writer。"
        }
    } catch {
        $enabled.Checked = $false
        $status.Text = $_.Exception.Message
    }
    $installed = Test-ModelQuickly
    $modelStatus.Text = if ($installed) {
        "Qwen2.5 1.5B Q4_K_M 已安装并将在使用时再次校验。"
    } else {
        "模型未安装。按需下载约 1.04 GiB；来源 Hugging Face，Apache-2.0。"
    }
    $downloadButton.Enabled = -not $installed
    $removeButton.Enabled = $installed
    $runButton.Enabled = $installed -and $enabled.Checked -and $enabled.Enabled
}

$enabled.Add_CheckedChanged({
    try {
        $settings = Ensure-AiSettings (Read-Settings)
        if ([bool]$settings.strict_privacy_mode) {
            $enabled.Checked = $false
            return
        }
        $settings.ai.enable_short_completion = $false
        $settings.ai.enable_rewrite = $enabled.Checked
        $settings.ai.enable_translation = $enabled.Checked
        Write-Settings $settings
        Refresh-WriterState
    } catch {
        Show-WriterMessage $_.Exception.Message ([System.Windows.Forms.MessageBoxIcon]::Warning)
    }
})

$downloadWorker = New-Object System.ComponentModel.BackgroundWorker
$downloadWorker.WorkerReportsProgress = $false
$downloadWorker.Add_DoWork({
    New-Item -ItemType Directory -Force -Path $modelDirectory | Out-Null
    if (Test-Path $modelStagingPath) {
        Remove-Item -Force $modelStagingPath
    }
    $client = New-Object System.Net.WebClient
    try {
        $client.Headers["User-Agent"] = "PrivatePinyin-Writer/1"
        $client.DownloadFile($modelUrl, $modelStagingPath)
    } finally {
        $client.Dispose()
    }
    if ((Get-Item $modelStagingPath).Length -ne $modelSize) {
        throw "模型大小校验失败。"
    }
    $actualHash = (Get-FileHash -Algorithm SHA256 -Path $modelStagingPath).Hash.ToLowerInvariant()
    if ($actualHash -ne $modelSha256) {
        throw "模型 SHA-256 校验失败。"
    }
    Move-Item -Force -Path $modelStagingPath -Destination $modelPath
})
$downloadWorker.Add_RunWorkerCompleted({
    $progress.Visible = $false
    $downloadButton.Enabled = $true
    if ($_.Error) {
        if (Test-Path $modelStagingPath) { Remove-Item -Force $modelStagingPath }
        Show-WriterMessage "模型下载或校验失败。请检查网络后重试。" ([System.Windows.Forms.MessageBoxIcon]::Warning)
    } else {
        $status.Text = "模型已安装。首次生成建议时需要几秒钟冷启动。"
    }
    Refresh-WriterState
})

$downloadButton.Add_Click({
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "将从固定的 Hugging Face 官方来源下载 Qwen2.5 1.5B Q4_K_M（约 1.04 GiB），并校验大小与 SHA-256。模型只保存在本机。继续吗？",
        "下载 Writer 模型",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $downloadButton.Enabled = $false
    $progress.Visible = $true
    $modelStatus.Text = "正在下载并校验模型，请不要关闭窗口..."
    $downloadWorker.RunWorkerAsync()
})

$removeButton.Add_Click({
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "确定移除本机 Writer 模型吗？普通拼音和 AI Lite 不受影响。",
        "移除 Writer 模型",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    if (Test-Path $modelDirectory) { Remove-Item -Recurse -Force $modelDirectory }
    Refresh-WriterState
})

$writerWorker = New-Object System.ComponentModel.BackgroundWorker
$writerWorker.Add_DoWork({
    param($sender, $eventArgs)
    $arguments = [object[]]$eventArgs.Argument
    $eventArgs.Result = Invoke-WriterHelper -Feature ([byte]$arguments[0]) -Source ([string]$arguments[1])
})
$writerWorker.Add_RunWorkerCompleted({
    $runButton.Enabled = $true
    if ($_.Error) {
        $status.Text = "生成失败或超时。普通拼音和原文不受影响。"
        return
    }
    try {
        $settings = Ensure-AiSettings (Read-Settings)
        if ([bool]$settings.strict_privacy_mode -or -not [bool]$settings.ai.enable_rewrite -or -not [bool]$settings.ai.enable_translation) {
            $results.Items.Clear()
            $status.Text = "设置已变化，生成结果已丢弃。"
            Refresh-WriterState
            return
        }
    } catch {
        $results.Items.Clear()
        $status.Text = "无法复核 Writer 设置，生成结果已丢弃。"
        return
    }
    $results.Items.Clear()
    foreach ($suggestion in @($_.Result)) {
        [void]$results.Items.Add([string]$suggestion)
    }
    $status.Text = "已生成 $($results.Items.Count) 条建议；双击可复制。"
})

$runButton.Add_Click({
    $text = $sourceBox.Text.Trim()
    if (-not $text) {
        Show-WriterMessage "请先输入需要处理的文字。" ([System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    if ($writerWorker.IsBusy) { return }
    $settings = Ensure-AiSettings (Read-Settings)
    if ([bool]$settings.strict_privacy_mode -or -not [bool]$settings.ai.enable_rewrite -or -not [bool]$settings.ai.enable_translation) {
        Show-WriterMessage "请先关闭严格隐私模式，并明确启用本地 Writer。" ([System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    $featureCode = [byte]($feature.SelectedIndex + 2)
    $results.Items.Clear()
    $status.Text = "正在本机启动模型并生成建议..."
    $runButton.Enabled = $false
    $writerWorker.RunWorkerAsync([object[]]@($featureCode, $text))
})

$results.Add_DoubleClick({
    if ($null -ne $results.SelectedItem) {
        [System.Windows.Forms.Clipboard]::SetText([string]$results.SelectedItem)
        $status.Text = "建议已复制。"
    }
})

Refresh-WriterState
[void]$form.ShowDialog()
