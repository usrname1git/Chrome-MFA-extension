[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Install-Autom8edVault.ps1")
Add-Type -AssemblyName UIAutomationClient
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Autom8edInstallerTestWindow {
    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr window, int id);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SendMessageTimeoutW(IntPtr window, uint message,
        IntPtr wparam, IntPtr lparam, uint flags, uint timeout, out IntPtr result);
}
'@

function Find-Window([int]$ProcessId, [string]$ClassName) {
    $condition = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessId),
        [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ClassNameProperty, $ClassName))
    return [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
}

function Click-TestButton($Window, [int]$Id) {
    $button = [Autom8edInstallerTestWindow]::GetDlgItem([IntPtr]$Window.Current.NativeWindowHandle, $Id)
    if (-not $button -or -not [Autom8edInstallerTestWindow]::IsWindowVisible($button)) { throw "Expected confirmation control $Id is not visible." }
    $result = [IntPtr]::Zero
    $sent = [Autom8edInstallerTestWindow]::SendMessageTimeoutW($button, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero, 2, 3000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) { throw "Could not click the fixture confirmation." }
}

function Get-TestProcesses([string]$Profile) {
    return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='brave.exe' OR Name='msedge.exe'" | Where-Object {
        $_.Name -in @("chrome.exe", "brave.exe", "msedge.exe") -and
        $_.CommandLine -and $_.CommandLine.Contains($Profile)
    })
}

function Run-LiveCase($Browser, [string]$Profile, [string]$Source, [string]$Mode) {
    $out = Join-Path $fixture ($Browser.Name + "-" + $Mode + ".out.txt")
    $err = Join-Path $fixture ($Browser.Name + "-" + $Mode + ".err.txt")
    $timeout = if ($Mode -eq "InvalidManifest") { 10 } else { 45 }
    $packageName = "Autom8ed Installer Fixture"
    $packageVersion = "0.0.1"
    if ($Mode -eq "ActualMFA") {
        $packageManifest = Get-Content -LiteralPath (Join-Path $Source "manifest.json") -Raw | ConvertFrom-Json
        $packageName = $packageManifest.name
        $packageVersion = $packageManifest.version
    }
    $arguments = @(
        "--browser", (ConvertTo-NativeArgument $Browser.Exe),
        "--path", (ConvertTo-NativeArgument $Source),
        "--name", (ConvertTo-NativeArgument $packageName),
        "--version", $packageVersion,
        "--user-data-dir", (ConvertTo-NativeArgument $Profile),
        "--timeout", "$timeout"
    )
    $process = Start-Process -FilePath $helper -ArgumentList $arguments -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    try {
        $deadline = (Get-Date).AddSeconds(65)
        $confirmed = $false
        while (-not $process.HasExited -and (Get-Date) -lt $deadline) {
            $window = Find-Window $process.Id "Autom8edVaultSetup"
            if ($window -and -not $confirmed) {
                $button = [Autom8edInstallerTestWindow]::GetDlgItem([IntPtr]$window.Current.NativeWindowHandle, 100)
                if ($button -and [Autom8edInstallerTestWindow]::IsWindowVisible($button)) {
                    $testBrowsers = @(Get-TestProcesses $Profile | Where-Object { $_.CommandLine -notmatch '--type=' })
                    if ($testBrowsers.Count -ne 1) { throw "Cannot prove which isolated browser profile is awaiting confirmation." }
                    if ($Mode -notin @("Consent", "Cancel")) { throw "Developer-mode consent unexpectedly appeared in $Mode." }
                    $browserWindow = Find-Window ([int]$testBrowsers[0].ProcessId) "Chrome_WidgetWin_1"
                    $hostElement = $browserWindow.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
                        [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty, "devMode"))
                    $toggle = $hostElement.FindFirst([System.Windows.Automation.TreeScope]::Subtree,
                        [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::IsTogglePatternAvailableProperty, $true))
                    if ($toggle.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -ne [System.Windows.Automation.ToggleState]::Off) {
                        throw "Developer mode changed before confirmation."
                    }
                    Click-TestButton $window $(if ($Mode -eq "Cancel") { 2 } else { 100 })
                    $confirmed = $true
                }
            }
            Start-Sleep -Milliseconds 150
            $process.Refresh()
        }
        if (-not $process.HasExited) { throw "$($Browser.Name) $Mode exceeded its test deadline." }
        $process.WaitForExit()
        $expected = if ($Mode -eq "Cancel") { 130 } elseif ($Mode -eq "InvalidManifest") { 1 } else { 0 }
        if ($process.ExitCode -ne $expected) {
            $diagnostic = @()
            $registered = @()
            foreach ($preferencesName in @("Preferences", "Secure Preferences")) {
                $preferencesPath = Join-Path $Profile ("Default\" + $preferencesName)
                if (Test-Path -LiteralPath $preferencesPath) {
                    $preferences = Get-Content -LiteralPath $preferencesPath -Raw | ConvertFrom-Json
                    if ($preferences.extensions.settings) {
                        foreach ($setting in $preferences.extensions.settings.PSObject.Properties) {
                            $registered += [pscustomobject]@{
                                Id = $setting.Name
                                Name = $setting.Value.manifest.name
                                Version = $setting.Value.manifest.version
                                Path = $setting.Value.path
                                State = $setting.Value.state
                            }
                        }
                    }
                }
            }
            foreach ($testBrowser in @(Get-TestProcesses $Profile | Where-Object { $_.CommandLine -notmatch '--type=' })) {
                $browserWindow = Find-Window ([int]$testBrowser.ProcessId) "Chrome_WidgetWin_1"
                if ($browserWindow) {
                    $address = $browserWindow.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
                        [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty, "view_1012"))
                    $diagnostic += [pscustomobject]@{
                        Title = $browserWindow.Current.Name
                        Location = if ($address) { $address.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } else { "No address bar" }
                    }
                }
            }
            throw "$($Browser.Name) $Mode failed (exit $($process.ExitCode)): $(Get-Content -LiteralPath $out,$err -Raw) Isolated browser: $($diagnostic | ConvertTo-Json -Compress) Registered fixtures: $($registered | ConvertTo-Json -Compress)"
        }
        if ($Mode -in @("Consent", "Cancel") -and -not $confirmed) { throw "The consent control was not exercised." }
        if ($expected -eq 0 -and (Get-Content -LiteralPath $out -Raw) -notmatch "Verified installed and enabled") {
            throw "Success without installation proof."
        }
        if ($Mode -eq "InvalidManifest" -and (Get-Content -LiteralPath $err -Raw) -notmatch "Browser rejected the extension") {
            throw "A browser load error must be detected directly, not left waiting for the deadline."
        }
        Write-Host "PASS: $($Browser.Name) $Mode"
    } finally {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
        $process.Dispose()
    }
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ("Autom8ed live installer " + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $fixture | Out-Null
$helper = Join-Path $PSScriptRoot "build\installer\autom8ed-installer.exe"
$profiles = @()
try {
    $source = Join-Path $fixture "extension with spaces"
    $badSource = Join-Path $fixture "invalid extension"
    New-Item -ItemType Directory -Path $source,$badSource | Out-Null
    [IO.File]::WriteAllText((Join-Path $source "manifest.json"),
        '{"manifest_version":3,"name":"Autom8ed Installer Fixture","version":"0.0.1","description":"Permission-free, disposable installer fixture."}',
        [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $badSource "manifest.json"), '{"invalid":true}', [Text.UTF8Encoding]::new($false))
    $actualManifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot "manifest.json") -Raw | ConvertFrom-Json
    $script:installRoot = Join-Path $fixture "MFA install target"
    $actualPayload = Copy-Extension $PSScriptRoot
    $detectedBrowsers = @(Get-DetectedBrowsers)
    if (-not $detectedBrowsers.Count) { throw "No supported browser is installed for live verification." }
    foreach ($browser in $detectedBrowsers) {
        $profile = Join-Path $fixture ($browser.Name + " profile")
        $cancelProfile = Join-Path $fixture ($browser.Name + " cancel profile")
        $profiles += $profile,$cancelProfile
        Run-LiveCase $browser $profile $source "Consent"
        Run-LiveCase $browser $profile $source "AlreadyInstalled"
        Run-LiveCase $browser $profile $actualPayload.Dir "ActualMFA"
        Run-LiveCase $browser $cancelProfile $source "Cancel"
        Run-LiveCase $browser $profile $badSource "InvalidManifest"
    }
} finally {
    foreach ($profile in $profiles) {
        $owned = @(Get-TestProcesses $profile)
        foreach ($process in $owned) {
            $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($process.ProcessId)"
            if ($current -and $current.CommandLine -and $current.CommandLine.Contains($profile)) {
                Stop-Process -Id $process.ProcessId -Force -ErrorAction Continue
            }
        }
    }
    Start-Sleep -Seconds 1
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
