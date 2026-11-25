[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$OutputDirectory
)

# Builds the one-click download package for a GitHub release:
#   build\dist\codex-repair-toolbox-windows.zip
# The asset name never changes, so the README link
# releases/latest/download/codex-repair-toolbox-windows.zip always points to the newest release.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot 'dist' }
$repoRoot = Split-Path -Parent $PSScriptRoot
$folderName = "Codex修复工具箱-$Version"
$assetName = 'codex-repair-toolbox-windows.zip'

$include = @(
    '双击启动脚本.cmd',
    'README.md',
    'scripts\CodexRepairToolbox.ps1',
    'scripts\Repair-CodexRuntime.ps1',
    'scripts\Set-CodexLoginMode.ps1',
    'scripts\lib\CodexLoginMode.ps1',
    'docs\organization-settings-cli-path.md',
    'docs\images\toolbox.png',
    'docs\images\toolbox-login-on.png',
    'docs\images\toolbox-repaired.png'
)

$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-release-" + [guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $staging $folderName

try {
    foreach ($relative in $include) {
        $source = Join-Path $repoRoot $relative
        if (-not (Test-Path -LiteralPath $source)) { throw "Missing file: $relative" }
        $target = Join-Path $packageRoot $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
    }

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $zipPath = Join-Path $OutputDirectory $assetName
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    # UTF-8 entry names (with the UTF-8 flag) so Chinese file names survive Windows "Extract All".
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $staging, $zipPath,
        [System.IO.Compression.CompressionLevel]::Optimal, $false,
        [System.Text.Encoding]::UTF8)

    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Host "package: $zipPath"
    Write-Host "size:    $((Get-Item -LiteralPath $zipPath).Length) bytes"
    Write-Host "sha256:  $hash"
} finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
}
