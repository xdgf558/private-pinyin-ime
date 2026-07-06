param(
    [Parameter(Mandatory = $true)]
    [string]$DllPath
)

$ErrorActionPreference = "Stop"
$resolved = Resolve-Path $DllPath
& "$env:SystemRoot\System32\regsvr32.exe" /u /s $resolved
Write-Host "Unregistered PrivatePinyin TSF DLL: $resolved"
