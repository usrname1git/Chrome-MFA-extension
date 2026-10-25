[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$fixture = Join-Path ([IO.Path]::GetTempPath()) ("Autom8ed MFA package test " + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $fixture | Out-Null

try {
    $assets = Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object {
        $_.Extension -in @(".js", ".html", ".css", ".png") -or
        $_.Name -in @("manifest.json", "Install.cmd", "Install-Autom8edVault.ps1")
    }
    foreach ($asset in $assets) {
        Copy-Item -LiteralPath $asset.FullName -Destination (Join-Path $fixture $asset.Name)
    }
    $helperDir = Join-Path $fixture "build\installer"
    New-Item -ItemType Directory -Path $helperDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "build\installer\autom8ed-installer.exe") -Destination $helperDir

    & (Join-Path $PSScriptRoot "Pack-Autom8edVault.ps1") -RepoRoot $fixture
    $manifest = Get-Content -LiteralPath (Join-Path $fixture "manifest.json") -Raw | ConvertFrom-Json
    $dist = Join-Path $fixture "dist"

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $setup = [IO.Compression.ZipFile]::OpenRead(
        (Join-Path $dist "autom8ed-vault-$($manifest.version)-setup.zip")
    )
    try {
        $entries = @($setup.Entries | ForEach-Object { $_.FullName.Replace("\", "/") })
        if ($entries.Count -eq 0) { throw "The setup ZIP is empty." }
        $loose = @($entries | Where-Object { -not $_.StartsWith("autom8ed-mfa/", [StringComparison]::Ordinal) })
        if ($loose.Count -ne 0) { throw "The setup ZIP contains entries outside autom8ed-mfa/." }
        foreach ($required in @(
            "autom8ed-mfa/Install.cmd",
            "autom8ed-mfa/Install-Autom8edVault.ps1",
            "autom8ed-mfa/autom8ed-installer.exe",
            "autom8ed-mfa/extension/manifest.json"
        )) {
            if ($entries -cnotcontains $required) { throw "The setup ZIP is missing $required." }
        }
    } finally {
        $setup.Dispose()
    }

    $store = [IO.Compression.ZipFile]::OpenRead(
        (Join-Path $dist "autom8ed-vault-$($manifest.version)-chrome-web-store.zip")
    )
    try {
        $entries = @($store.Entries | ForEach-Object { $_.FullName.Replace("\", "/") })
        if ($entries -cnotcontains "manifest.json") { throw "The Web Store ZIP must have manifest.json at its root." }
        if (@($entries | Where-Object { $_.StartsWith("autom8ed-mfa/", [StringComparison]::Ordinal) }).Count -ne 0) {
            throw "The Web Store ZIP must not use the setup wrapper folder."
        }
    } finally {
        $store.Dispose()
    }

    Write-Host "PASS: setup ZIP has one autom8ed-mfa root; Web Store ZIP stays flat."
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction Stop
}
