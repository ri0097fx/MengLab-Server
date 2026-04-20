$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "install_menglab_windows.ps1")

$runSetup = Read-Host "続けて資格情報セットアップを実行しますか? [Y/n]"
if ([string]::IsNullOrWhiteSpace($runSetup) -or $runSetup -match '^[Yy]$') {
    powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "wpfetch_relay.ps1") setup
}

Write-Host ""
Write-Host "完了。利用例:"
Write-Host "  menglab"
Write-Host "  menglab about/"
