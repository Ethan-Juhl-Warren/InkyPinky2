# Builds and runs the engine.
#
# The C side of src/engine/pak needs cl and lib, which only exist once the MSVC
# environment is loaded, so this finds vcvars and runs the Makefile through it
# rather than repeating the compiler flags here. miniz is only recompiled when
# its source changes, so a normal run is just the Odin build.
#
# The engine is a shared library and the runtime is the front end executable
# that links it. Both are built by default. -Engine and -Runtime narrow that to
# one half, which is worth doing when you are only touching one of them: the
# engine link is the slow one.
#
#   .\run.ps1                    build both and run
#   .\run.ps1 -Build             build both
#   .\run.ps1 -Engine            build build\engine.dll only
#   .\run.ps1 -Runtime           build build\inky.exe only
#   .\run.ps1 -Runtime -Build    build the runtime without running it
#
# Passing both -Engine and -Runtime is the same as passing neither. Nothing is
# run when the runtime was not part of the build, since there would be no point
# launching an executable this invocation did not produce.

param(
	[switch]$Engine,
	[switch]$Runtime,
	[switch]$Build
)

$ErrorActionPreference = "Stop"

if (-not $Engine -and -not $Runtime) {
	$Engine = $true
	$Runtime = $true
}

if ($Engine -and $Runtime) {
	$target = "windows"
} elseif ($Engine) {
	$target = "windows-engine"
} else {
	$target = "windows-runtime"
}

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

cmd /c "call `"$vcvars`" >nul 2>&1 && nmake /nologo $target"
if ($LASTEXITCODE -ne 0) {
	exit $LASTEXITCODE
}

if (-not $Build -and $Runtime) {
	& .\build\inky.exe
	exit $LASTEXITCODE
}
