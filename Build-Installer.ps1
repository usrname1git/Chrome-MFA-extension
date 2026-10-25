[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path -LiteralPath $vswhere)) { throw "Visual Studio C++ Build Tools are required to build the installer." }
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $vs) { throw "No Visual Studio x64 C++ toolchain was found." }
$vcvars = Join-Path $vs "VC\Auxiliary\Build\vcvars64.bat"
$out = Join-Path $PSScriptRoot "build\installer"
New-Item -ItemType Directory -Path $out -Force | Out-Null
$source = Join-Path $PSScriptRoot "Install-BrowserExtension.cpp"
$exe = Join-Path $out "autom8ed-installer.exe"
$obj = Join-Path $out "autom8ed-installer.obj"
$cmd = Join-Path ([Environment]::GetFolderPath("System")) "cmd.exe"
$installerTools = Split-Path -Parent $vswhere
& $cmd /d /c "set `"PATH=$installerTools;%PATH%`" && call `"$vcvars`" >nul && cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /DUNICODE /D_UNICODE /Fe:`"$exe`" /Fo:`"$obj`" `"$source`" /link uiautomationcore.lib ole32.lib oleaut32.lib user32.lib gdi32.lib bcrypt.lib"
if ($LASTEXITCODE -ne 0) { throw "Native installer build failed." }
Write-Host "Built $exe"
$fixtureSource = Join-Path $PSScriptRoot "Test-InstallerProcess.cpp"
$fixtureExe = Join-Path $out "installer-process-fixture.exe"
$fixtureObj = Join-Path $out "installer-process-fixture.obj"
& $cmd /d /c "set `"PATH=$installerTools;%PATH%`" && call `"$vcvars`" >nul && cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /Fe:`"$fixtureExe`" /Fo:`"$fixtureObj`" `"$fixtureSource`""
if ($LASTEXITCODE -ne 0) { throw "Installer process fixture build failed." }
