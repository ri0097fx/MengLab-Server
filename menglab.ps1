param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ArgsList
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Core = Join-Path $ScriptDir "wpfetch_relay.ps1"

if (-not (Test-Path $Core)) {
    throw "wpfetch_relay.ps1 が見つかりません: $Core"
}

if (-not $ArgsList -or $ArgsList.Count -eq 0) {
    & $Core preview
    exit $LASTEXITCODE
}

$first = $ArgsList[0].ToLowerInvariant()
if ($first -in @("setup", "reset", "fetch", "preview")) {
    & $Core @ArgsList
    exit $LASTEXITCODE
}

# 先頭がパス指定なら preview とみなす
& $Core preview @ArgsList
exit $LASTEXITCODE
