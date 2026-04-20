param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ArgsList
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Core = Join-Path $ScriptDir "wpfetch_relay.ps1"

if (-not (Test-Path $Core)) {
    throw "Missing file: $Core"
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

# Treat first arg as preview path
& $Core preview @ArgsList
exit $LASTEXITCODE
