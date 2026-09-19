# Build Chrome Web Store zip + GitHub setup zip. Does not launch or kill browsers
# except an optional headless pack-extension pass.
[CmdletBinding()]
param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$manifestPath = Join-Path $RepoRoot "manifest.json"
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$version = [string]$manifest.version
if (-not $version) { throw "manifest.json has no version." }

$files = @(
    "manifest.json",
    "background.js",
    "popup.html", "popup.js",
    "manager.html", "manager.js",
    "injector.js", "auto-injector.js",
    "crypto-helper.js",
    "styles.css",
    "icon16.png", "icon32.png", "icon48.png", "icon64.png", "icon128.png"
)
foreach ($name in $files) {
    $path = Join-Path $RepoRoot $name
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing extension file: $name" }
}

$dist = Join-Path $RepoRoot "dist"
$webstore = Join-Path $dist "webstore"
$setup = Join-Path $dist "setup"
$setupExt = Join-Path $setup "extension"
Remove-Item -LiteralPath $dist -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $webstore, $setupExt -Force | Out-Null

foreach ($name in $files) {
    Copy-Item -LiteralPath (Join-Path $RepoRoot $name) -Destination (Join-Path $webstore $name)
    Copy-Item -LiteralPath (Join-Path $RepoRoot $name) -Destination (Join-Path $setupExt $name)
}
Copy-Item -LiteralPath (Join-Path $RepoRoot "Install-Autom8edVault.ps1") -Destination (Join-Path $setup "Install-Autom8edVault.ps1")
Copy-Item -LiteralPath (Join-Path $RepoRoot "Install.cmd") -Destination (Join-Path $setup "Install.cmd")

Add-Type -AssemblyName System.IO.Compression.FileSystem
function Write-Zip([string]$SourceDir, [string]$ZipPath) {
    if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($SourceDir, $ZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
}

$storeZip = Join-Path $dist "autom8ed-vault-$version-chrome-web-store.zip"
$setupZip = Join-Path $dist "autom8ed-vault-$version-setup.zip"
Write-Zip $webstore $storeZip
Write-Zip $setup $setupZip

Write-Host "Chrome Web Store zip: $storeZip"
Write-Host "GitHub setup zip:     $setupZip"
Write-Host "Version: $version"
