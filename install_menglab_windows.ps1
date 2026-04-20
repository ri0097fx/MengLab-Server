$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LauncherPs1 = Join-Path $ScriptDir "menglab.ps1"
$CorePs1 = Join-Path $ScriptDir "wpfetch_relay.ps1"

if (-not (Test-Path $LauncherPs1)) { throw "menglab.ps1 がありません: $LauncherPs1" }
if (-not (Test-Path $CorePs1)) { throw "wpfetch_relay.ps1 がありません: $CorePs1" }

$UserBin = Join-Path $HOME "bin"
if (-not (Test-Path $UserBin)) {
    New-Item -Path $UserBin -ItemType Directory | Out-Null
}

$CmdPath = Join-Path $UserBin "menglab.cmd"
$CmdBody = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "$LauncherPs1" %*
"@
Set-Content -Path $CmdPath -Value $CmdBody -Encoding ASCII

$answer = Read-Host "User PATH に $UserBin を追加しますか? [y/N]"
if ($answer -match '^[Yy]$') {
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $UserPath) { $UserPath = "" }
    $parts = $UserPath -split ";" | Where-Object { $_ -ne "" }
    if ($parts -notcontains $UserBin) {
        $newPath = if ($UserPath.Trim().Length -eq 0) { $UserBin } else { "$UserPath;$UserBin" }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "User PATH に追加しました: $UserBin"
    } else {
        Write-Host "User PATH は設定済みです: $UserBin"
    }
} else {
    Write-Host "PATH は変更していません。"
    Write-Host "フルパス実行例:"
    Write-Host "  $CmdPath"
}

Write-Host "インストール完了: $CmdPath"
Write-Host "新しい PowerShell/CMD を開いて実行:"
Write-Host "  menglab"
Write-Host "  menglab about/"
Write-Host "  menglab setup"
