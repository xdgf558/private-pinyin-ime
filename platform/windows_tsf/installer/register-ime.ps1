param(
    [Parameter(Mandatory = $true)]
    [string]$DllPath
)

$ErrorActionPreference = "Stop"
$resolved = Resolve-Path $DllPath
& "$env:SystemRoot\System32\regsvr32.exe" /s $resolved
Write-Host "Registered PrivatePinyin TSF DLL: $resolved"
