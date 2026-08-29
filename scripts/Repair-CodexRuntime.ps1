[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Yes,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Write-Step([string]$Message) {
    Write-Host "[Codex repair] $Message"
}

function Get-DirectoryStats([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Exists = $false; FileCount = 0; SizeMB = 0 }
    }

    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)
    $bytes = ($files | Measure-Object Length -Sum).Sum
    if ($null -eq $bytes) { $bytes = 0 }

    [pscustomobject]@{
        Exists = $true
        FileCount = $files.Count
        SizeMB = [math]::Round($bytes / 1MB, 1)
    }
}

function Test-ManifestMatches([string]$ManifestPath, [object]$SourceManifest) {
    if (-not (Test-Path -LiteralPath $ManifestPath)) { return $false }

    try {
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
        return (
            $manifest.runtime_archive_name -eq $SourceManifest.runtime_archive_name -and
            $manifest.runtime_archive_version -eq $SourceManifest.runtime_archive_version -and
            $manifest.node_version -eq $SourceManifest.node_version
        )
    } catch {
        return $false
    }
}

function Copy-TreeAsPlainFiles([string]$SourceRoot, [string]$DestinationRoot) {
    $sourceRootFull = (Get-Item -LiteralPath $SourceRoot).FullName.TrimEnd('\')
    New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null

    $dirs = @(Get-ChildItem -LiteralPath $sourceRootFull -Recurse -Directory -Force)
    foreach ($dir in $dirs) {
        $relativePath = $dir.FullName.Substring($sourceRootFull.Length).TrimStart('\')
        New-Item -ItemType Directory -Path (Join-Path $DestinationRoot $relativePath) -Force | Out-Null
    }

    $files = @(Get-ChildItem -LiteralPath $sourceRootFull -Recurse -File -Force)
    $copied = 0

    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($sourceRootFull.Length).TrimStart('\')
        $targetPath = Join-Path $DestinationRoot $relativePath
        $targetParent = Split-Path -Parent $targetPath
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null

        $inputStream = $null
        $outputStream = $null
        try {
            $inputStream = [System.IO.File]::Open($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $outputStream = [System.IO.File]::Open($targetPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $inputStream.CopyTo($outputStream, 1048576)
        } finally {
            if ($null -ne $outputStream) { $outputStream.Dispose() }
            if ($null -ne $inputStream) { $inputStream.Dispose() }
        }

        [System.IO.File]::SetLastWriteTimeUtc($targetPath, $file.LastWriteTimeUtc)
        $copied++
        if (($copied % 500) -eq 0) {
            Write-Step "copied $copied / $($files.Count) files"
        }
    }

    return $files.Count
}

Write-Step "mode: $(if ($Apply) { 'APPLY' } else { 'DRY-RUN' })"

$package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $package) {
    throw 'OpenAI.Codex Appx package was not found for the current Windows user.'
}

$installLocation = $package.InstallLocation
$sourceRoot = Join-Path $installLocation 'app\resources\cua_node'
$sourceManifestPath = Join-Path $sourceRoot 'manifest.json'
$runtimeRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node'

if (-not (Test-Path -LiteralPath $sourceManifestPath)) {
    throw "Packaged Codex runtime manifest was not found: $sourceManifestPath"
}

$sourceManifest = Get-Content -LiteralPath $sourceManifestPath -Raw | ConvertFrom-Json
$sourceStats = Get-DirectoryStats $sourceRoot

Write-Step "Codex package: $($package.Version)"
Write-Step "packaged runtime: $($sourceManifest.runtime_archive_name)"
Write-Step "packaged runtime size: $($sourceStats.SizeMB) MB, files: $($sourceStats.FileCount)"
Write-Step "runtime cache root: $runtimeRoot"

$stagingDirs = @()
if (Test-Path -LiteralPath $runtimeRoot) {
    $stagingDirs = @(Get-ChildItem -LiteralPath $runtimeRoot -Force -Directory | Where-Object { $_.Name -match '^\.staging-([^-]+)-' })
}

$hashCandidates = @()
if ($stagingDirs.Count -gt 0) {
    $hashCandidates = @(
        $stagingDirs |
            Group-Object { if ($_.Name -match '^\.staging-([^-]+)-') { $matches[1] } } |
            ForEach-Object {
                [pscustomobject]@{
                    Hash = $_.Name
                    Count = $_.Count
                    Newest = ($_.Group | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
                }
            } |
            Sort-Object Newest -Descending
    )
}

$targetHash = $null
if ($hashCandidates.Count -gt 0) {
    $targetHash = $hashCandidates[0].Hash
    Write-Step "detected current runtime hash from staging: $targetHash ($($hashCandidates[0].Count) staging folders)"
} else {
    $matchingCacheDirs = @()
    if (Test-Path -LiteralPath $runtimeRoot) {
        $matchingCacheDirs = @(
            Get-ChildItem -LiteralPath $runtimeRoot -Force -Directory |
                Where-Object { $_.Name -notmatch '^\.staging-' -and $_.Name -notmatch 'backup' } |
                Where-Object { Test-ManifestMatches (Join-Path $_.FullName 'manifest.json') $sourceManifest }
        )
    }

    if ($matchingCacheDirs.Count -gt 0) {
        $stats = Get-DirectoryStats $matchingCacheDirs[0].FullName
        Write-Step "a matching runtime cache already exists: $($matchingCacheDirs[0].Name) ($($stats.SizeMB) MB, $($stats.FileCount) files)"
        if ($stats.FileCount -eq $sourceStats.FileCount -and $stats.SizeMB -eq $sourceStats.SizeMB) {
            Write-Step 'nothing to repair.'
            exit 0
        }

        $targetHash = $matchingCacheDirs[0].Name
        Write-Step "matching cache exists but looks incomplete; selected hash: $targetHash"
    } else {
        throw 'No .staging-* runtime folder was found, so the expected runtime hash cannot be determined. Open Codex once until it gets stuck, then run this script again.'
    }
}

$targetRoot = Join-Path $runtimeRoot $targetHash
$targetStats = Get-DirectoryStats $targetRoot
$currentHashStagingDirs = @($stagingDirs | Where-Object { $_.Name -like ".staging-$targetHash-*" })

Write-Step "target cache folder: $targetRoot"
Write-Step "current target state: exists=$($targetStats.Exists), size=$($targetStats.SizeMB) MB, files=$($targetStats.FileCount)"
Write-Step "staging folders to back up: $($currentHashStagingDirs.Count)"

if ($targetStats.Exists -and (Test-ManifestMatches (Join-Path $targetRoot 'manifest.json') $sourceManifest) -and $targetStats.FileCount -eq $sourceStats.FileCount -and $targetStats.SizeMB -eq $sourceStats.SizeMB) {
    Write-Step 'target cache is already complete and matches the installed package.'
    if (-not $NoLaunch) {
        Write-Step 'launching Codex for verification.'
        Start-Process "shell:AppsFolder\$($package.PackageFamilyName)!App"
    }
    exit 0
}

if (-not $Apply) {
    Write-Host ''
    Write-Step 'dry-run only. No files or processes were changed.'
    Write-Step 'to repair, run this script with -Apply. The .cmd launcher already does that.'
    exit 0
}

if (-not $Yes) {
    Write-Host ''
    Write-Host 'This repair will:'
    Write-Host "  1. Close running Codex/ChatGPT processes from the OpenAI.Codex package only."
    Write-Host "  2. Move incomplete staging runtime folders to a timestamped backup folder."
    Write-Host "  3. Rebuild only this cache folder: $targetRoot"
    Write-Host ''
    Write-Host 'It will NOT delete files, reset the app, touch chat/login data, or change Windows settings.'
    $answer = Read-Host 'Type YES to continue'
    if ($answer -ne 'YES') {
        Write-Step 'cancelled by user.'
        exit 1
    }
}

Write-Step 'closing Codex desktop processes from the OpenAI.Codex package.'
$codexProcesses = @(Get-Process -Name ChatGPT -ErrorAction SilentlyContinue | Where-Object {
    try { $_.Path -like '*\OpenAI.Codex_*\app\ChatGPT.exe' } catch { $false }
})
foreach ($process in $codexProcesses) {
    Stop-Process -Id $process.Id -Force
}
Start-Sleep -Seconds 2

New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null

if ($currentHashStagingDirs.Count -gt 0) {
    $stagingBackup = Join-Path $runtimeRoot ("staging-backup-$targetHash-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $stagingBackup -Force | Out-Null
    foreach ($dir in $currentHashStagingDirs) {
        Move-Item -LiteralPath $dir.FullName -Destination $stagingBackup
    }
    Write-Step "moved $($currentHashStagingDirs.Count) staging folders to: $stagingBackup"
}

if (Test-Path -LiteralPath $targetRoot) {
    $targetBackup = Join-Path $runtimeRoot ("$targetHash-backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Move-Item -LiteralPath $targetRoot -Destination $targetBackup
    Write-Step "moved existing target cache to: $targetBackup"
}

Write-Step 'copying packaged runtime as plain, unencrypted files.'
$copiedCount = Copy-TreeAsPlainFiles $sourceRoot $targetRoot
$finalStats = Get-DirectoryStats $targetRoot
$finalManifestPath = Join-Path $targetRoot 'manifest.json'
$finalManifestItem = Get-Item -LiteralPath $finalManifestPath

Write-Step "copied files: $copiedCount"
Write-Step "final target size: $($finalStats.SizeMB) MB, files: $($finalStats.FileCount)"
Write-Step "final manifest attributes: $($finalManifestItem.Attributes)"

if ($finalStats.FileCount -ne $sourceStats.FileCount -or $finalStats.SizeMB -ne $sourceStats.SizeMB) {
    throw 'Verification failed: copied runtime does not match packaged runtime file count/size.'
}

if (-not (Test-ManifestMatches $finalManifestPath $sourceManifest)) {
    throw 'Verification failed: copied manifest does not match packaged runtime manifest.'
}

Write-Step 'runtime cache repair completed.'

if (-not $NoLaunch) {
    Write-Step 'launching Codex.'
    Start-Process "shell:AppsFolder\$($package.PackageFamilyName)!App"
    Start-Sleep -Seconds 20

    $windows = @(Get-Process -Name ChatGPT -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -like '*\OpenAI.Codex_*\app\ChatGPT.exe' -and $_.MainWindowHandle -ne 0 } catch { $false }
    })

    if ($windows.Count -gt 0) {
        foreach ($window in $windows) {
            Write-Step "window: title='$($window.MainWindowTitle)', responding=$($window.Responding), pid=$($window.Id)"
        }
    } else {
        Write-Step 'Codex launched, but no main window was detected yet. If it is still opening, wait a little longer.'
    }
}
