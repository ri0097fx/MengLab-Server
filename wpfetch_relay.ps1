param(
    [ValidateSet("setup", "reset", "fetch", "preview")]
    [string]$Command = "fetch",
    [string]$PagePath = ""
)

$ErrorActionPreference = "Stop"

# Relay / target defaults
$RelayHost = if ($env:RELAY_HOST) { $env:RELAY_HOST } else { "172.24.160.42" }
$RelayUser = if ($env:RELAY_USER) { $env:RELAY_USER } else { "ihpc" }
$RelaySshPort = if ($env:RELAY_SSH_PORT) { [int]$env:RELAY_SSH_PORT } else { 20002 }
$RemoteReversePort = if ($env:REMOTE_REVERSE_PORT) { [int]$env:REMOTE_REVERSE_PORT } else { 28081 }
$LocalForwardPort = if ($env:LOCAL_FORWARD_PORT) { [int]$env:LOCAL_FORWARD_PORT } else { 18081 }
$WpBasePath = if ($env:WP_BASE_PATH) { $env:WP_BASE_PATH } else { "/lab_server/" }
$WpUpstreamOrigin = if ($env:WP_UPSTREAM_ORIGIN) { $env:WP_UPSTREAM_ORIGIN } else { "http://192.168.50.138" }

# Safer default: key auth only on Windows
$RelaySshKey = if ($env:RELAY_SSH_KEY) { $env:RELAY_SSH_KEY } else { "$HOME\.ssh\id_ed25519" }

$CredDir = Join-Path $env:APPDATA "wpfetch"
$CredFile = Join-Path $CredDir "credentials.xml"

function Ensure-CredDir {
    if (-not (Test-Path $CredDir)) {
        New-Item -ItemType Directory -Path $CredDir | Out-Null
    }
}

function Save-Creds {
    Ensure-CredDir
    $wpUser = Read-Host "WordPress username to save"
    $wpPass = Read-Host "WordPress password to save" -AsSecureString
    $relayPass = Read-Host "Relay SSH password to save" -AsSecureString
    $obj = [pscustomobject]@{
        WpUser = $wpUser
        WpPass = $wpPass
        RelayPass = $relayPass
    }
    $obj | Export-Clixml -Path $CredFile
    Write-Host "Saved credentials: $CredFile"
}

function Reset-Creds {
    if (Test-Path $CredFile) {
        Remove-Item $CredFile -Force
        Write-Host "Deleted credentials: $CredFile"
    } else {
        Write-Host "No saved credentials found."
    }
}

function Load-Creds {
    if (-not (Test-Path $CredFile)) {
        throw "No credentials file. Run: .\wpfetch_relay.ps1 setup"
    }
    Import-Clixml -Path $CredFile
}

function SecureToPlain([securestring]$s) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Start-Tunnel {
    if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue)) {
        throw "ssh.exe not found. Install OpenSSH Client."
    }
    
    $sshArgs = @(
        "-N",
        "-p", "$RelaySshPort",
        "-L", "127.0.0.1:$LocalForwardPort`:127.0.0.1:$RemoteReversePort",
        "-o", "ExitOnForwardFailure=yes",
        "-o", "ServerAliveInterval=30",
        "-o", "ServerAliveCountMax=3",
        "-o", "StrictHostKeyChecking=yes",
        "-o", "PreferredAuthentications=publickey,password"
    )

    if (Test-Path $RelaySshKey) {
        $sshArgs += @(
            "-o", "IdentitiesOnly=yes",
            "-i", $RelaySshKey
        )
    }
    $sshArgs += "$RelayUser@$RelayHost"

    $relayPassPlain = if ($script:relayPass) { $script:relayPass } else { "" }
    $askPassFile = ""
    $askPassSecretFile = ""
    if (-not [string]::IsNullOrEmpty($relayPassPlain)) {
        $askPassSecretFile = Join-Path $env:TEMP ("wpfetch_askpass_secret_{0}.txt" -f [guid]::NewGuid().ToString("N"))
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($askPassSecretFile, $relayPassPlain, $utf8NoBom)
        $askPassFile = Join-Path $env:TEMP ("wpfetch_askpass_{0}.cmd" -f [guid]::NewGuid().ToString("N"))
        $askpassBody = "@echo off`r`nsetlocal`r`ntype ""{0}""`r`n" -f $askPassSecretFile
        [System.IO.File]::WriteAllText($askPassFile, $askpassBody, [System.Text.Encoding]::ASCII)
        $env:SSH_ASKPASS = $askPassFile
        $env:SSH_ASKPASS_REQUIRE = "force"
        $env:DISPLAY = "1"
    }

    $p = Start-Process -FilePath "ssh.exe" -ArgumentList $sshArgs -PassThru -NoNewWindow

    # Wait until local forward port is actually open.
    $ready = $false
    for ($i = 0; $i -lt 240; $i++) {
        if ($p.HasExited) { break }
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $iar = $tcp.BeginConnect("127.0.0.1", $LocalForwardPort, $null, $null)
            if ($iar.AsyncWaitHandle.WaitOne(200)) {
                $tcp.EndConnect($iar)
                $ready = $true
                $tcp.Close()
                break
            }
            $tcp.Close()
        } catch {
        }
        Start-Sleep -Milliseconds 500
    }

    if (-not $ready) {
        if (-not $p.HasExited) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
        if ($askPassFile -and (Test-Path $askPassFile)) {
            Remove-Item $askPassFile -Force -ErrorAction SilentlyContinue
        }
        if ($askPassSecretFile -and (Test-Path $askPassSecretFile)) {
            Remove-Item $askPassSecretFile -Force -ErrorAction SilentlyContinue
        }
        Remove-Item Env:SSH_ASKPASS, Env:SSH_ASKPASS_REQUIRE, Env:DISPLAY -ErrorAction SilentlyContinue
        $endpoint = "{0}@{1}:{2}" -f $RelayUser, $RelayHost, $RelaySshPort
        throw "Failed to open SSH tunnel. Check auth for $endpoint"
    }

    if ($askPassFile -and (Test-Path $askPassFile)) {
        Remove-Item $askPassFile -Force -ErrorAction SilentlyContinue
    }
    if ($askPassSecretFile -and (Test-Path $askPassSecretFile)) {
        Remove-Item $askPassSecretFile -Force -ErrorAction SilentlyContinue
    }
    Remove-Item Env:SSH_ASKPASS, Env:SSH_ASKPASS_REQUIRE, Env:DISPLAY -ErrorAction SilentlyContinue

    if ($p.HasExited) {
        $endpoint = "{0}@{1}:{2}" -f $RelayUser, $RelayHost, $RelaySshPort
        throw "Failed to open SSH tunnel. Check auth for $endpoint"
    }
    return $p
}

function Invoke-Curl([string[]]$CurlArgs) {
    $result = & curl.exe @CurlArgs
    return $result
}

if ($Command -eq "setup") {
    Save-Creds
    exit 0
}
if ($Command -eq "reset") {
    Reset-Creds
    exit 0
}

$creds = Load-Creds
$wpUser = $creds.WpUser
$wpPassPlain = SecureToPlain $creds.WpPass
$relayPass = ""
if ($creds.PSObject.Properties.Name -contains "RelayPass" -and $creds.RelayPass) {
    $relayPass = SecureToPlain $creds.RelayPass
}
if ([string]::IsNullOrEmpty($relayPass)) {
    $relayPassSecure = Read-Host "Relay SSH password" -AsSecureString
    $relayPass = SecureToPlain $relayPassSecure
}

$cookieFile = [System.IO.Path]::GetTempFileName()
$tunnelProc = $null

try {
    Write-Host "[1/3] Opening tunnel..."
    $tunnelProc = Start-Tunnel

    $baseUrl = "http://127.0.0.1:$LocalForwardPort$WpBasePath"
    $loginUrl = "${baseUrl}wp-login.php"
    $targetUrl = if ([string]::IsNullOrWhiteSpace($PagePath)) { $baseUrl } else { "$baseUrl$PagePath" }

    Write-Host "[2/3] Logging in..."
    Invoke-Curl @("-sS", "--fail", "-c", $cookieFile, "-b", $cookieFile, $loginUrl) | Out-Null
    $form = "log=$([uri]::EscapeDataString($wpUser))&pwd=$([uri]::EscapeDataString($wpPassPlain))&rememberme=forever&wp-submit=Log+In&testcookie=1&redirect_to=$([uri]::EscapeDataString($baseUrl))"
    $effective = Invoke-Curl @("-sS", "--fail", "--location", "-c", $cookieFile, "-b", $cookieFile, "-d", $form, "-o", "NUL", "-w", "%{url_effective}", $loginUrl)
    if ($effective -match "wp-login\.php") {
        throw "WordPress login failed. Run setup again and verify credentials."
    }

    Write-Host "[3/3] Fetching..."
    $html = Invoke-Curl @("-sS", "--fail", "-c", $cookieFile, "-b", $cookieFile, $targetUrl)
    if ($html -match "<title>(.*?)</title>") {
        Write-Host "Title: $($matches[1])"
    } else {
        Write-Host "Title not found. URL: $targetUrl"
    }

    if ($Command -eq "preview") {
        # Quick preview for Windows: rewrite absolute origin and open local file.
        $rewritten = $html.Replace($WpUpstreamOrigin, "http://127.0.0.1:$LocalForwardPort")
        $previewFile = Join-Path $env:TEMP "wpfetch_preview_$env:USERNAME.html"
        [System.IO.File]::WriteAllText($previewFile, $rewritten, [System.Text.Encoding]::UTF8)
        Write-Host "Preview file: $previewFile"
        Start-Process $previewFile | Out-Null
        Write-Host "Press Enter to close tunnel..."
        [void][System.Console]::ReadLine()
    }
}
finally {
    if ($tunnelProc -and -not $tunnelProc.HasExited) {
        Stop-Process -Id $tunnelProc.Id -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $cookieFile) {
        Remove-Item $cookieFile -Force -ErrorAction SilentlyContinue
    }
}
