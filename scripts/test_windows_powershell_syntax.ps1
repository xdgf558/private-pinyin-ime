$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$parseErrors = @()

Get-ChildItem -Path $repositoryRoot -Filter "*.ps1" -File -Recurse | ForEach-Object {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $_.FullName,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null
    foreach ($error in $errors) {
        $parseErrors += "$($_.FullName):$($error.Extent.StartLineNumber): $($error.Message)"
    }
}

if ($parseErrors.Count -gt 0) {
    throw ($parseErrors -join [Environment]::NewLine)
}

Write-Host "Windows PowerShell syntax checks passed."
