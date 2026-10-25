[CmdletBinding()]
param(
    [switch]$LiveBrowsers
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Install-Autom8edVault.ps1")

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    $caught = $false
    try { & $Action | Out-Null }
    catch {
        $caught = $true
        if ($_.Exception.Message -notlike $Pattern) { throw }
    }
    Assert-True $caught "Expected an explicit error matching $Pattern."
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ("Autom8ed installer test " + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    $detected = @("Chrome", "Edge", "Brave") | ForEach-Object {
        [pscustomobject]@{ Name = $_; Exe = "$_.exe"; Process = $_ }
    }
    Assert-True (@(Select-Browsers $detected @("Chrome,Brave")).Count -eq 2) "Comma-separated browser selection failed."
    Assert-True (@(Select-Browsers $detected @("chrome", "CHROME")).Count -eq 1) "Browser selection must be case-insensitive and unique."
    Assert-True (@(Select-Browsers $detected @("All")).Count -eq 3) "All must select every detected browser."
    Assert-Throws { Select-Browsers @($detected[0]) @("Chrome", "Edge") } "*not installed: Edge*"
    Assert-Throws { Select-Browsers $detected @("Firefox") } "*Unknown browser*"
    Assert-Throws { Select-Browsers @() @("All") } "*No Chrome*"

    $source = Join-Path $fixture "extension"
    New-Item -ItemType Directory -Path $source | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "manifest.json"), (Join-Path $PSScriptRoot "popup.js") -Destination $source
    Set-Content -LiteralPath (Join-Path $source "installer-only.cpp") -Value "not an extension asset"
    $script:installRoot = Join-Path $fixture "installed"
    $payload = Copy-Extension $source
    Assert-True (Test-Path -LiteralPath (Join-Path $payload.Dir "manifest.json")) "Extension manifest was not staged."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $payload.Dir "installer-only.cpp"))) "Installer code leaked into extension assets."
    Assert-True ($payload.Dir -eq (Join-Path $script:installRoot "1.0.0")) "Setup changed the legacy extension identity path."
    $upgrade = Get-Content -LiteralPath (Join-Path $source "manifest.json") -Raw | ConvertFrom-Json
    $upgrade.version = "1.0.2"
    $upgrade | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $source "manifest.json")
    $upgraded = Copy-Extension $source
    Assert-True ($upgraded.Dir -eq $payload.Dir) "A version update changed the path-derived extension ID."
    Assert-True ((Get-Content -LiteralPath (Join-Path $upgraded.Dir "manifest.json") -Raw | ConvertFrom-Json).version -eq "1.0.2") "Upgrade did not copy the new manifest."

    $script:codes = @{}
    $script:calls = [Collections.Generic.List[string]]::new()
    $nativeInvocation = ${function:Invoke-BrowserSetup}
    function Invoke-BrowserSetup($Browser, $Payload, $Manifest, [string]$Helper) {
        $script:calls.Add($Browser.Name)
        if ($script:codes[$Browser.Name] -eq "throw") { throw "fixture launch failure" }
        return $script:codes[$Browser.Name]
    }
    $manifest = [pscustomobject]@{ name = "Fixture"; version = "1.0.0" }
    $script:codes = @{ Chrome = 0; Edge = 0; Brave = 0 }
    Assert-True ((Install-SelectedBrowsers $detected $payload $manifest "fixture") -eq 0) "Successful browsers must produce exit zero."
    Assert-True ($script:calls.Count -eq 3) "Every selected browser must be attempted."
    $script:calls.Clear()
    $script:codes.Edge = 1
    Assert-True ((Install-SelectedBrowsers $detected $payload $manifest "fixture") -eq 1) "Partial failure was reported as success."
    Assert-True ($script:calls.Count -eq 3) "One browser failure must not skip the others."
    $script:calls.Clear()
    $script:codes.Edge = "throw"
    $result = Install-SelectedBrowsers $detected $payload $manifest "fixture" 2>$null
    Assert-True ($result -eq 1 -and $script:calls.Count -eq 3) "Launch errors must remain failures without skipping later browsers."
    $script:calls.Clear()
    $script:codes.Chrome = 130
    Assert-True ((Install-SelectedBrowsers $detected $payload $manifest "fixture") -eq 130) "Cancellation exit status was lost."
    Assert-True ($script:calls.Count -eq 1) "Cancellation must stop remaining browser installs."

    $helper = Join-Path $PSScriptRoot "build\installer\autom8ed-installer.exe"
    if (-not (Test-Path -LiteralPath $helper)) { throw "Run Build-Installer.ps1 before installer tests." }
    Set-Item -Path Function:\Invoke-BrowserSetup -Value $nativeInvocation
    $processFixture = Join-Path $PSScriptRoot "build\installer\installer-process-fixture.exe"
    $child = $null
    try {
        $code = Invoke-BrowserSetup $detected[0] $payload $manifest $processFixture
        Assert-True ($code -eq 7) "Helper exit status was not preserved."
        $childId = [int](Get-Content -LiteralPath (Join-Path $payload.Dir "child.pid") -Raw)
        $child = Get-Process -Id $childId
        Assert-True ($child.Path -eq $processFixture -and -not $child.HasExited) "Setup waited for the browser descendant to exit."
    } finally {
        if ($child) {
            if (-not $child.HasExited -and $child.Path -eq $processFixture) {
                Stop-Process -Id $child.Id -Force
                $child.WaitForExit()
            }
            $child.Dispose()
        }
    }
    $missingBrowser = [pscustomobject]@{ Name = "Chrome"; Exe = (Join-Path $fixture "missing browser.exe") }
    Assert-True ((Invoke-BrowserSetup $missingBrowser $payload $manifest $helper) -eq 1) "Native process exit status was lost."
    $packageRoot = Join-Path $fixture "autom8ed-mfa"
    $packageSource = Join-Path $packageRoot "extension"
    New-Item -ItemType Directory -Path $packageSource -Force | Out-Null
    $packageHelper = Join-Path $packageRoot "autom8ed-installer.exe"
    Copy-Item -LiteralPath $helper -Destination $packageHelper
    $script:here = Join-Path $fixture "unrelated working directory"
    Assert-True ((Get-InstallerHelper $packageSource) -eq $packageHelper) "Wrapped online setup did not resolve its bundled helper."
    $process = Start-Process -FilePath $helper -ArgumentList @("--unknown", "fixture") -NoNewWindow -Wait -PassThru -RedirectStandardError (Join-Path $fixture "unknown-error.txt")
    Assert-True ($process.ExitCode -ne 0) "Native installer accepted unknown arguments."
    $process = Start-Process -FilePath $helper -ArgumentList @("--browser", "missing.exe", "--path", (ConvertTo-NativeArgument $source), "--name", "Fixture", "--version", "1.0.0") -NoNewWindow -Wait -PassThru -RedirectStandardError (Join-Path $fixture "missing-error.txt")
    Assert-True ($process.ExitCode -ne 0) "Native installer accepted a missing browser."
    Write-Host "PASS: browser selection, staging, failure aggregation, cancellation and native argument checks."
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}

if ($LiveBrowsers) {
    & (Join-Path $PSScriptRoot "Test-InstallerLive.ps1")
}
