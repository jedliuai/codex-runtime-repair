# Shared helpers for the Codex login fix (os error 10013).
#
# Background: the Codex login flow starts a local callback server on
# 127.0.0.1:1455. On some Windows machines the WinNAT service reserves a
# dynamic TCP port range that happens to include 1455, so binding fails with
# "os error 10013". Temporarily stopping WinNAT releases the reservation;
# starting it again afterwards restores Docker / WSL2 / Hyper-V NAT networking.
#
# This file is dot-sourced by Set-CodexLoginMode.ps1 and CodexRepairToolbox.ps1.
# It only touches the WinNAT service and one small state file:
#   %LOCALAPPDATA%\codex-runtime-repair\login-mode.json

$script:CodexLoginPort = 1455

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CodexLoginStateFile {
    return (Join-Path $env:LOCALAPPDATA 'codex-runtime-repair\login-mode.json')
}

function Get-ExcludedTcpPortRanges {
    $ranges = @()
    try {
        $lines = @(& netsh.exe interface ipv4 show excludedportrange protocol=tcp 2>$null)
    } catch {
        return $ranges
    }

    foreach ($line in $lines) {
        if ($line -match '^\s*(\d+)\s+(\d+)') {
            $ranges += [pscustomobject]@{
                Start = [int]$matches[1]
                End   = [int]$matches[2]
            }
        }
    }
    return $ranges
}

function Get-PortOwnerName([int]$Port) {
    try {
        $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $connection) {
            $process = Get-Process -Id $connection.OwningProcess -ErrorAction Stop
            return $process.ProcessName
        }
    } catch {
    }
    return $null
}

function Test-CodexLoginPort {
    param([int]$Port = $script:CodexLoginPort)

    $range = Get-ExcludedTcpPortRanges | Where-Object { $Port -ge $_.Start -and $Port -le $_.End } | Select-Object -First 1
    $rangeText = $null
    if ($null -ne $range) { $rangeText = '{0}-{1}' -f $range.Start, $range.End }

    $state = 'Free'
    $errorCode = $null
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
    try {
        $listener.Start()
    } catch {
        $socketError = $_.Exception
        while ($null -ne $socketError -and -not ($socketError -is [System.Net.Sockets.SocketException])) {
            $socketError = $socketError.InnerException
        }
        if ($null -ne $socketError) { $errorCode = $socketError.ErrorCode }

        switch ($errorCode) {
            10013 { $state = 'Reserved' }
            10048 { $state = 'InUse' }
            default { $state = 'Error' }
        }
    } finally {
        try { $listener.Stop() } catch { }
    }

    $owner = $null
    if ($state -eq 'InUse') { $owner = Get-PortOwnerName $Port }

    return [pscustomobject]@{
        Port          = $Port
        State         = $state
        ErrorCode     = $errorCode
        ExcludedRange = $rangeText
        Owner         = $owner
    }
}

function Get-WinNatStatus {
    $service = Get-Service -Name winnat -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        return [pscustomobject]@{ Exists = $false; Status = $null; StartType = $null }
    }

    $startType = $null
    try { $startType = [string]$service.StartType } catch { }

    return [pscustomobject]@{
        Exists    = $true
        Status    = [string]$service.Status
        StartType = $startType
    }
}

function Get-CodexLoginModeStatus {
    $winNat = Get-WinNatStatus
    $stateFile = Get-CodexLoginStateFile
    $stoppedByTool = $false
    $stoppedAt = $null

    if (Test-Path -LiteralPath $stateFile) {
        if ($winNat.Exists -and $winNat.Status -eq 'Stopped') {
            $stoppedByTool = $true
            try { $stoppedAt = (Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json).stoppedAt } catch { }
        } else {
            # WinNAT is running again (reboot, or restored elsewhere): the marker is stale.
            Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
        }
    }

    return [pscustomobject]@{
        WinNat        = $winNat
        LoginModeOn   = ($winNat.Exists -and $winNat.Status -eq 'Stopped')
        StoppedByTool = $stoppedByTool
        StoppedAt     = $stoppedAt
        Port          = Test-CodexLoginPort
    }
}

function Enable-CodexLoginMode {
    if (-not (Test-IsAdministrator)) {
        throw 'Administrator rights are required to stop the WinNAT service.'
    }

    $winNat = Get-WinNatStatus
    if (-not $winNat.Exists) {
        throw 'The WinNAT service was not found on this computer.'
    }

    if ($winNat.Status -ne 'Stopped') {
        Stop-Service -Name winnat -ErrorAction Stop

        $stateFile = Get-CodexLoginStateFile
        New-Item -ItemType Directory -Path (Split-Path -Parent $stateFile) -Force | Out-Null
        $marker = [pscustomobject]@{ stoppedAt = (Get-Date).ToString('o'); port = $script:CodexLoginPort }
        Set-Content -LiteralPath $stateFile -Value ($marker | ConvertTo-Json -Compress) -Encoding UTF8
    }

    # The reserved range is released asynchronously; give it a moment before re-testing.
    Start-Sleep -Milliseconds 600
    return Get-CodexLoginModeStatus
}

function Disable-CodexLoginMode {
    if (-not (Test-IsAdministrator)) {
        throw 'Administrator rights are required to start the WinNAT service.'
    }

    $winNat = Get-WinNatStatus
    if (-not $winNat.Exists) {
        throw 'The WinNAT service was not found on this computer.'
    }

    if ($winNat.Status -ne 'Running') {
        Start-Service -Name winnat -ErrorAction Stop
    }

    Remove-Item -LiteralPath (Get-CodexLoginStateFile) -Force -ErrorAction SilentlyContinue
    return Get-CodexLoginModeStatus
}
