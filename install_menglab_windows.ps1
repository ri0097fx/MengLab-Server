$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LauncherPs1 = Join-Path $ScriptDir "menglab.ps1"
$CorePs1 = Join-Path $ScriptDir "wpfetch_relay.ps1"

if (-not (Test-Path $LauncherPs1)) { throw "Missing file: $LauncherPs1" }
if (-not (Test-Path $CorePs1)) { throw "Missing file: $CorePs1" }

$UserBin = Join-Path $HOME "bin"
if (-not (Test-Path $UserBin)) {
    New-Item -Path $UserBin -ItemType Directory | Out-Null
}

$CmdPath = Join-Path $UserBin "menglab.cmd"
$CmdBody = "@echo off`r`n" + 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $LauncherPs1 + '" %*'
Set-Content -Path $CmdPath -Value $CmdBody -Encoding ASCII

$answer = Read-Host "Add $UserBin to User PATH? [y/N]"
if ($answer -match '^[Yy]$') {
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $UserPath) { $UserPath = "" }
    $parts = $UserPath -split ";" | Where-Object { $_ -ne "" }
    if ($parts -notcontains $UserBin) {
        $newPath = if ($UserPath.Trim().Length -eq 0) { $UserBin } else { "$UserPath;$UserBin" }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "Added to User PATH: $UserBin"
    } else {
        Write-Host "User PATH already contains: $UserBin"
    }
} else {
    Write-Host "PATH unchanged."
    Write-Host "Run with full path:"
    Write-Host "  $CmdPath"
}

Write-Host "Install complete: $CmdPath"
Write-Host "Open a new PowerShell/CMD and run:"
Write-Host "  menglab"
Write-Host "  menglab about/"
Write-Host "  menglab setup"
