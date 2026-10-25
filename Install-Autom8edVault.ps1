# Install into the selected normal browser profiles without debugging ports.
[CmdletBinding()]
param(
    [string[]]$Browsers = @("All"),
    [switch]$Online
)

$ErrorActionPreference = "Stop"
$here = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$installRoot = Join-Path $env:LOCALAPPDATA "Autom8edVault"
$downloadWorkspace = $null

function Get-SourceExtension {
    $candidates = @(
        (Join-Path $here "extension"),
        $here
    )
    foreach ($dir in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $dir "manifest.json")) { return $dir }
    }
    return $null
}

function Install-FromGitHub {
    $api = "https://api.github.com/repos/usrname1git/Chrome-MFA-extension/releases/latest"
    $release = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "Autom8edVault-Installer" }
    $asset = @($release.assets) | Where-Object { $_.name -like "*-setup.zip" } | Select-Object -First 1
    if (-not $asset) { throw "Latest GitHub release has no *-setup.zip asset." }
    $script:downloadWorkspace = Join-Path ([IO.Path]::GetTempPath()) ("Autom8edVault-Setup-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $script:downloadWorkspace | Out-Null
    $zip = Join-Path $script:downloadWorkspace "setup.zip"
    $extract = Join-Path $script:downloadWorkspace "unpacked"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $extract)
    $nested = @(Get-ChildItem -LiteralPath $extract -Recurse -File -Filter "manifest.json")
    if ($nested.Count -ne 1) { throw "Setup zip must contain exactly one extension manifest." }
    return $nested[0].DirectoryName
}

function Get-DetectedBrowsers {
    $rows = @(
        [pscustomobject]@{
            Name = "Chrome"
            Exe = @(
                "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
                "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
                "${env:LOCALAPPDATA}\Google\Chrome\Application\chrome.exe"
            )
            Process = "chrome"
        }
        [pscustomobject]@{
            Name = "Edge"
            Exe = @(
                "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
                "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe",
                "${env:LOCALAPPDATA}\Microsoft\Edge\Application\msedge.exe"
            )
            Process = "msedge"
        }
        [pscustomobject]@{
            Name = "Brave"
            Exe = @(
                "${env:LOCALAPPDATA}\BraveSoftware\Brave-Browser\Application\brave.exe",
                "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe"
            )
            Process = "brave"
        }
    )
    foreach ($row in $rows) {
        $exe = @($row.Exe) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($exe) {
            [pscustomobject]@{
                Name = $row.Name
                Exe = $exe
                Process = $row.Process
            }
        }
    }
}

function Select-Browsers($detected, $want) {
    if (-not $detected) { throw "No Chrome, Edge, or Brave install found." }
    $allowed = @("Chrome", "Edge", "Brave", "All")
    $names = @($want | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ } | Select-Object -Unique)
    foreach ($name in $names) {
        if (-not ($allowed | Where-Object { $_ -eq $name })) {
            throw "Unknown browser '$name'. Use All, Chrome, Edge, or Brave."
        }
    }
    if ($names.Count -eq 0 -or ($names | Where-Object { $_ -eq "All" })) { return $detected }
    $missing = @($names | Where-Object { $_ -notin $detected.Name })
    if ($missing.Count) { throw "Requested browser(s) not installed: $($missing -join ', ')" }
    $picked = @($detected | Where-Object {
        $installed = $_.Name
        @($names | Where-Object { $_ -eq $installed }).Count -gt 0
    })
    return $picked
}

function Copy-Extension([string]$Source) {
    # Chromium derives unpacked IDs from this path; retain the original directory across upgrades.
    $dest = Join-Path $installRoot "1.0.0"
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -File | Where-Object {
        $_.Extension -in @(".js", ".html", ".css", ".png") -or $_.Name -eq "manifest.json"
    } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Force
    }
    return [pscustomobject]@{ Dir = $dest }
}

function Get-InstallerHelper([string]$Source) {
    $candidates = @(
        (Join-Path $here "autom8ed-installer.exe"),
        (Join-Path (Split-Path $Source -Parent) "autom8ed-installer.exe"),
        (Join-Path $here "build\installer\autom8ed-installer.exe")
    )
    $helper = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $helper) { throw "The native installer is missing. Extract the complete setup ZIP, or run Build-Installer.ps1 in a source checkout." }
    return $helper
}

function ConvertTo-NativeArgument([string]$Value) {
    # Windows argument parsing doubles backslashes before literal or closing quotes.
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function Invoke-BrowserSetup($Browser, $Payload, $Manifest, [string]$Helper) {
    $arguments = @(
        "--browser", (ConvertTo-NativeArgument $Browser.Exe),
        "--path", (ConvertTo-NativeArgument $Payload.Dir),
        "--name", (ConvertTo-NativeArgument $Manifest.name),
        "--version", (ConvertTo-NativeArgument $Manifest.version)
    )
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Helper
    $info.Arguments = $arguments -join " "
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw "The native installer did not start." }
        $process.WaitForExit()
        return $process.ExitCode
    }
    finally { $process.Dispose() }
}

function Install-SelectedBrowsers($Targets, $Payload, $Manifest, [string]$Helper) {
    $failed = @()
    foreach ($target in $Targets) {
        Write-Host ""
        Write-Host "Setting up $($target.Name)..."
        try {
            $code = Invoke-BrowserSetup $target $Payload $Manifest $Helper
        } catch {
            Write-Error "$($target.Name): $($_.Exception.Message)" -ErrorAction Continue
            $failed += $target.Name
            continue
        }
        if ($code -eq 130) {
            Write-Host "Setup cancelled. Remaining browsers were not changed."
            return 130
        }
        if ($code -ne 0) {
            Write-Host "$($target.Name): installation was NOT confirmed (exit $code)." -ForegroundColor Red
            $failed += $target.Name
        } else {
            Write-Host "$($target.Name): installed and verified." -ForegroundColor Green
        }
    }
    if ($failed.Count) {
        Write-Host "Setup incomplete for: $($failed -join ', ')." -ForegroundColor Red
        return 1
    }
    return 0
}

function Invoke-Installer {
    $mutex = [Threading.Mutex]::new($false, "Local\Autom8edVault.Setup")
    $held = $false
    try {
        try { $held = $mutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] {
            $held = $true
            Write-Warning "Previous setup stopped unexpectedly; starting a fresh verified attempt."
        }
        if (-not $held) { throw "Another Autom8ed Vault installer is already running." }
        $detected = @(Get-DetectedBrowsers)
        $want = @($Browsers)
        if ($want.Count -eq 1 -and $want[0] -eq "All" -and $detected.Count -gt 1) {
            Write-Host "Found: $($detected.Name -join ', ')"
            $answer = Read-Host "Install to which? [A]ll, or comma-separated names (Chrome,Edge,Brave)"
            if ($answer -and $answer -notmatch '^\s*(A|All)\s*$') { $want = @($answer) }
        }
        $targets = @(Select-Browsers $detected $want)
        $source = if ($Online) { Install-FromGitHub } else { Get-SourceExtension }
        if (-not $source) {
            Write-Host "No local extension files. Downloading the latest GitHub setup zip..."
            $source = Install-FromGitHub
        }
        $manifest = Get-Content -LiteralPath (Join-Path $source "manifest.json") -Raw | ConvertFrom-Json
        $version = [string]$manifest.version
        if ($version -notmatch '^\d{1,5}(\.\d{1,5}){0,3}$' -or [string]::IsNullOrWhiteSpace($manifest.name)) {
            throw "The extension manifest has an invalid version or name."
        }
        $helper = Get-InstallerHelper $source
        $payload = Copy-Extension $source
        return (Install-SelectedBrowsers $targets $payload $manifest $helper)
    } finally {
        try {
            if ($script:downloadWorkspace) {
                Remove-Item -LiteralPath $script:downloadWorkspace -Recurse -Force
                $script:downloadWorkspace = $null
            }
        } finally {
            if ($held) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
        }
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    try { exit (Invoke-Installer) }
    catch {
        Write-Error $_ -ErrorAction Continue
        exit 1
    }
}
