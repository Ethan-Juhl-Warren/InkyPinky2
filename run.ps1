# Builds and runs the engine.
#
# The C side of src/pak needs cl and lib, which only exist once the MSVC
# environment is loaded, so this finds vcvars and runs the Makefile through it
# rather than repeating the compiler flags here. miniz is only recompiled when
# its source changes, so a normal run is just the Odin build.
#
#   .\run.ps1           build and run
#   .\run.ps1 -Build    build only

param([switch]$Build)

$ErrorActionPreference = "Stop"

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
	throw "vswhere.exe not found. Install the Visual Studio Build Tools with the C++ workload."
}

$install = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $install) {
	throw "No MSVC toolchain found. Install the Visual Studio Build Tools with the C++ workload."
}

$vcvars = Join-Path $install "VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) {
	throw "vcvars64.bat not found under $install"
}

cmd /c "call `"$vcvars`" >nul 2>&1 && nmake /nologo windows"
if ($LASTEXITCODE -ne 0) {
	exit $LASTEXITCODE
}

if (-not $Build) {
	& .\build\inky.exe
	exit $LASTEXITCODE
}
