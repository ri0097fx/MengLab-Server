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
        # Auto-add host key only on first contact; keep checking afterward.
        "-o", "StrictHostKeyChecking=accept-new",
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

function Get-CookieHeaderFromNetscapeFile([string]$Path) {
    if (-not (Test-Path $Path)) { return "" }
    $pairs = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content -Path $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith("#") -and -not $line.StartsWith("#HttpOnly_")) { continue }
        $parts = $line -split "`t"
        if ($parts.Count -ge 7) {
            $pairs.Add(("{0}={1}" -f $parts[5], $parts[6]))
        }
    }
    return ($pairs -join "; ")
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
$previewJob = $null

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
    $htmlRaw = Invoke-Curl @("-sS", "--fail", "-c", $cookieFile, "-b", $cookieFile, $targetUrl)
    $html = if ($htmlRaw -is [array]) { ($htmlRaw -join "`n") } else { [string]$htmlRaw }
    $titleMatch = [regex]::Match($html, "<title>(.*?)</title>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($titleMatch.Success) {
        Write-Host ("Title: {0}" -f $titleMatch.Groups[1].Value)
    } else {
        Write-Host "Title not found. URL: $targetUrl"
    }

    if ($Command -eq "preview") {
        $previewPort = if ($env:WPFETCH_PREVIEW_PORT) { [int]$env:WPFETCH_PREVIEW_PORT } else { 18781 }
        $initialPath = if ([string]::IsNullOrWhiteSpace($PagePath)) {
            $WpBasePath
        } else {
            ("{0}/{1}" -f $WpBasePath.TrimEnd("/"), $PagePath.TrimStart("/"))
        }
        if (-not $initialPath.StartsWith("/")) { $initialPath = "/$initialPath" }
        $previewOrigin = "http://127.0.0.1:$previewPort"
        $previewUrl = "$previewOrigin$initialPath"
        $cookieHeader = Get-CookieHeaderFromNetscapeFile $cookieFile

        $proxyScript = {
            param($PreviewPort, $LocalForwardPort, $CookieHeader, $UpstreamOrigin, $InitialPath)
            $previewOrigin = "http://127.0.0.1:$PreviewPort"
            $forwardOrigin = "http://127.0.0.1:$LocalForwardPort"
            $listener = New-Object System.Net.HttpListener
            $listener.Prefixes.Add("$previewOrigin/")
            $listener.Start()
            try {
                while ($listener.IsListening) {
                    $ctx = $listener.GetContext()
                    $rawPath = $ctx.Request.RawUrl
                    if ([string]::IsNullOrWhiteSpace($rawPath) -or $rawPath -eq "/") {
                        $rawPath = $InitialPath
                    }
                    if (-not $rawPath.StartsWith("/")) { $rawPath = "/$rawPath" }
                    $targetUrl = "$forwardOrigin$rawPath"

                    try {
                        $req = [System.Net.HttpWebRequest]::Create($targetUrl)
                        $req.Method = $ctx.Request.HttpMethod
                        $req.AllowAutoRedirect = $false
                        $req.UserAgent = "wpfetch-preview-ps"
                        if (-not [string]::IsNullOrWhiteSpace($CookieHeader)) {
                            $req.Headers["Cookie"] = $CookieHeader
                        }
                        if ($ctx.Request.ContentLength64 -gt 0) {
                            $out = $req.GetRequestStream()
                            try { $ctx.Request.InputStream.CopyTo($out) } finally { $out.Close() }
                        }

                        try {
                            $resp = [System.Net.HttpWebResponse]$req.GetResponse()
                        } catch [System.Net.WebException] {
                            if ($_.Exception.Response) {
                                $resp = [System.Net.HttpWebResponse]$_.Exception.Response
                            } else {
                                throw
                            }
                        }

                        $ctx.Response.StatusCode = [int]$resp.StatusCode
                        foreach ($key in $resp.Headers.AllKeys) {
                            if ($key -in @("Transfer-Encoding", "Content-Length", "Connection", "Keep-Alive")) { continue }
                            $value = $resp.Headers[$key]
                            if ($key -eq "Location") {
                                $value = $value.Replace($UpstreamOrigin, $previewOrigin).Replace($forwardOrigin, $previewOrigin)
                            }
                            $ctx.Response.Headers[$key] = $value
                        }
                        $stream = $resp.GetResponseStream()
                        $ms = New-Object System.IO.MemoryStream
                        try {
                            $stream.CopyTo($ms)
                            $bytes = $ms.ToArray()
                            $ctx.Response.ContentLength64 = $bytes.Length
                            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                        } finally {
                            $stream.Close()
                            $ms.Close()
                            $resp.Close()
                        }
                    } catch {
                        $body = [System.Text.Encoding]::UTF8.GetBytes("proxy error")
                        $ctx.Response.StatusCode = 502
                        $ctx.Response.ContentType = "text/plain; charset=utf-8"
                        $ctx.Response.ContentLength64 = $body.Length
                        $ctx.Response.OutputStream.Write($body, 0, $body.Length)
                    } finally {
                        $ctx.Response.OutputStream.Close()
                    }
                }
            } finally {
                $listener.Stop()
                $listener.Close()
            }
        }

        $previewJob = Start-Job -ScriptBlock $proxyScript -ArgumentList @($previewPort, $LocalForwardPort, $cookieHeader, $WpUpstreamOrigin, $initialPath)
        Start-Sleep -Milliseconds 700
        Write-Host "Preview URL: $previewUrl"
        Start-Process $previewUrl | Out-Null
        Write-Host "Press Enter to close tunnel..."
        [void][System.Console]::ReadLine()
    }
}
finally {
    if ($previewJob) {
        Stop-Job -Job $previewJob -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $previewJob -Force -ErrorAction SilentlyContinue | Out-Null
    }
    if ($tunnelProc -and -not $tunnelProc.HasExited) {
        Stop-Process -Id $tunnelProc.Id -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $cookieFile) {
        Remove-Item $cookieFile -Force -ErrorAction SilentlyContinue
    }
}
