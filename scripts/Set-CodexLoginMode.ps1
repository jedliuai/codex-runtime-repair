[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(ParameterSetName = 'On')]
    [switch]$On,

    [Parameter(ParameterSetName = 'Off')]
    [switch]$Off
)

# Login fix for "failed to start login server ... (os error 10013)".
#
#   .\Set-CodexLoginMode.ps1         status only, changes nothing
#   .\Set-CodexLoginMode.ps1 -On     stop WinNAT so Codex can bind its login port
#   .\Set-CodexLoginMode.ps1 -Off    start WinNAT again (run this after signing in)
#
# -On and -Off need an elevated (Run as administrator) PowerShell.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'lib\CodexLoginMode.ps1')

function Write-Step([string]$Message) {
    Write-Host "[Codex login] $Message"
}

function Write-LoginStatus($Status) {
    if (-not $Status.WinNat.Exists) {
        Write-Step 'winnat service: not found'
    } else {
        Write-Step "winnat service: $($Status.WinNat.Status) (start type: $($Status.WinNat.StartType))"
    }

    $port = $Status.Port
    $detail = $port.State
    if ($port.ExcludedRange) { $detail += ", inside excluded range $($port.ExcludedRange)" }
    if ($port.Owner) { $detail += ", used by $($port.Owner)" }
    if ($port.State -eq 'Error' -and $port.ErrorCode) { $detail += ", socket error $($port.ErrorCode)" }
    Write-Step "login port $($port.Port): $detail"

    if ($Status.StoppedByTool) {
        Write-Step "login mode: ON (WinNAT stopped by this tool at $($Status.StoppedAt))"
    } elseif ($Status.LoginModeOn) {
        Write-Step 'login mode: WinNAT is stopped, but not by this tool'
    } else {
        Write-Step 'login mode: OFF'
    }
}

if ($PSCmdlet.ParameterSetName -eq 'Status') {
    $status = Get-CodexLoginModeStatus
    Write-LoginStatus $status
    Write-Host ''
    if ($status.Port.State -eq 'Reserved') {
        Write-Step 'the login port is reserved by Windows. Run with -On (as administrator), sign in to Codex, then run with -Off.'
    } elseif ($status.StoppedByTool) {
        Write-Step 'remember to run with -Off after signing in, so Docker / WSL2 networking comes back.'
    } else {
        Write-Step 'status only. Nothing was changed.'
    }
    exit 0
}

if (-not (Test-IsAdministrator)) {
    throw 'Please run this from an elevated PowerShell (Run as administrator).'
}

if ($On) {
    Write-Step 'stopping the WinNAT service. Docker / WSL2 NAT networking may pause until you run -Off.'
    $status = Enable-CodexLoginMode
    Write-LoginStatus $status
    Write-Host ''
    Write-Step 'now go back to Codex and click "Continue sign-in". When you are signed in, run this script with -Off.'
    exit 0
}

if ($Off) {
    Write-Step 'starting the WinNAT service.'
    $status = Disable-CodexLoginMode
    Write-LoginStatus $status
    exit 0
}
