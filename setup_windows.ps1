$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "install_menglab_windows.ps1")

$runSetup = Read-Host "Run credential setup now? [Y/n]"
if ([string]::IsNullOrWhiteSpace($runSetup) -or $runSetup -match '^[Yy]$') {
    powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "wpfetch_relay.ps1") setup
}

Write-Host ""
Write-Host "Done. Examples:"
Write-Host "  menglab"
Write-Host "  menglab about/"
