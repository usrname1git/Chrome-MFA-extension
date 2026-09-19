# Install Autom8ed Vault into Chrome / Edge / Brave. Does not kill browsers.
# Do not put ValidateSet on a [string[]] parameter named Browser: PowerShell
# treats $browser and $Browser as the same variable, and assigning an array
# to it validates as "System.String[]" instead of each name.
[CmdletBinding()]
param(
    [string[]]$Browsers = @("All"),
    [switch]$Online
)

$ErrorActionPreference = "Stop"
$here = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$installRoot = Join-Path $env:LOCALAPPDATA "Autom8edVault"

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
    $zip = Join-Path $env:TEMP "autom8ed-vault-setup.zip"
    $extract = Join-Path $env:TEMP "autom8ed-vault-setup"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
    if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $extract)
    $nested = Get-ChildItem -LiteralPath $extract -Recurse -Filter "manifest.json" |
        Where-Object { $_.DirectoryName -notmatch '\\dist\\' } |
        Select-Object -First 1
    if (-not $nested) { throw "setup zip did not contain manifest.json." }
    return $nested.DirectoryName
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
            ExtensionsKey = "HKCU:\Software\Google\Chrome\Extensions"
            PolicyKey = "HKCU:\Software\Policies\Google\Chrome\ExtensionInstallForcelist"
        }
        [pscustomobject]@{
            Name = "Edge"
            Exe = @(
                "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
                "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"
            )
            Process = "msedge"
            ExtensionsKey = "HKCU:\Software\Microsoft\Edge\Extensions"
            PolicyKey = "HKCU:\Software\Policies\Microsoft\Edge\ExtensionInstallForcelist"
        }
        [pscustomobject]@{
            Name = "Brave"
            Exe = @(
                "${env:LOCALAPPDATA}\BraveSoftware\Brave-Browser\Application\brave.exe",
                "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe"
            )
            Process = "brave"
            ExtensionsKey = "HKCU:\Software\BraveSoftware\Brave-Browser\Extensions"
            PolicyKey = "HKCU:\Software\Policies\BraveSoftware\BraveBrowser\ExtensionInstallForcelist"
        }
    )
    foreach ($row in $rows) {
        $exe = @($row.Exe) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($exe) {
            [pscustomobject]@{
                Name = $row.Name
                Exe = $exe
                Process = $row.Process
                ExtensionsKey = $row.ExtensionsKey
                PolicyKey = $row.PolicyKey
            }
        }
    }
}

function Select-Browsers($detected, $want) {
    if (-not $detected) { throw "No Chrome, Edge, or Brave install found." }
    $allowed = @("Chrome", "Edge", "Brave", "All")
    $names = @($want | Where-Object { $_ })
    foreach ($name in $names) {
        if (-not ($allowed | Where-Object { $_ -eq $name })) {
            throw "Unknown browser '$name'. Use All, Chrome, Edge, or Brave."
        }
    }
    if ($names.Count -eq 0 -or ($names | Where-Object { $_ -eq "All" })) { return $detected }
    $picked = @($detected | Where-Object {
        $installed = $_.Name
        @($names | Where-Object { $_ -eq $installed }).Count -gt 0
    })
    if (-not $picked) { throw "Requested browser(s) not installed: $($names -join ', ')" }
    return $picked
}

function Copy-Extension([string]$Source, [string]$Version) {
    $dest = Join-Path $installRoot $Version
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Force
    }
    $crxSrc = @(
        (Join-Path $here "autom8ed-vault-$Version.crx"),
        (Join-Path (Split-Path $Source -Parent) "autom8ed-vault-$Version.crx"),
        (Join-Path $Source "..\..\dist\autom8ed-vault-$Version.crx")
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    $crxDest = $null
    if ($crxSrc) {
        $crxDest = Join-Path $installRoot "autom8ed-vault-$Version.crx"
        Copy-Item -LiteralPath $crxSrc -Destination $crxDest -Force
    }
    return [pscustomobject]@{ Dir = $dest; Crx = $crxDest }
}

function Register-Browser($browser, $payload, [string]$Version) {
    $idKey = Join-Path $browser.ExtensionsKey "autom8edvault"
    New-Item -Path $idKey -Force | Out-Null
    if ($payload.Crx) {
        New-ItemProperty -Path $idKey -Name "path" -Value $payload.Crx -PropertyType String -Force | Out-Null
    } else {
        New-ItemProperty -Path $idKey -Name "path" -Value $payload.Dir -PropertyType String -Force | Out-Null
    }
    New-ItemProperty -Path $idKey -Name "version" -Value $Version -PropertyType String -Force | Out-Null
    $running = Get-Process -Name $browser.Process -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host ("{0} is already open. The vault is registered; it shows up after you close that browser and open it again. Not killing it." -f $browser.Name)
        return
    }
    $extArg = "--load-extension=`"$($payload.Dir)`""
    Start-Process -FilePath $browser.Exe -ArgumentList @($extArg)
    Write-Host ("Started {0} with the vault loaded." -f $browser.Name)
}

$source = if ($Online) { Install-FromGitHub } else { Get-SourceExtension }
if (-not $source) {
    Write-Host "No local extension files. Downloading the latest GitHub setup zip..."
    $source = Install-FromGitHub
}

$manifest = Get-Content -LiteralPath (Join-Path $source "manifest.json") -Raw | ConvertFrom-Json
$version = [string]$manifest.version
$detected = @(Get-DetectedBrowsers)
$want = @($Browsers)
if (@($want | Where-Object { $_ -eq "All" }) -and -not $Online -and $Host.UI.RawUI -and $detected.Count -gt 1) {
    Write-Host "Found: $($detected.Name -join ', ')"
    $answer = Read-Host "Install to which? [A]ll, or comma names (Chrome,Edge,Brave)"
    if ($answer -and $answer -notmatch '^\s*A') {
        $want = @($answer -split '[, ]+' | Where-Object { $_ })
    }
}
$targets = Select-Browsers $detected $want
$payload = Copy-Extension $source $version
foreach ($target in $targets) {
    Register-Browser $target $payload $version
}

Write-Host ""
Write-Host "Installed to $installRoot"
Write-Host "Pin the puzzle-piece icon once it appears."
Write-Host "Chrome Web Store upload zip is built by Pack-Autom8edVault.ps1 (dist\*-chrome-web-store.zip)."
