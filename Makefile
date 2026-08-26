# Builds the engine, and the vendored miniz C library that src/engine/pak links
# against.
#
# The miniz rules below were written by Claude Opus 5 (Anthropic) on 2026-08-25.
# The compiler flags are not arbitrary and two of them have been measured, see
# src/engine/pak/README.md before changing them.
#
#   Linux     make linux
#   Windows   nmake windows     (from a Developer Command Prompt, so cl is on PATH)
#
# Those build the engine and the runtime. Either half can be built on its own
# with the -engine and -runtime targets, which is the point of splitting them:
# a front end change does not need the engine relinked, and vice versa.
#
#   nmake windows-engine    make linux-engine     the shared library alone
#   nmake windows-runtime   make linux-runtime    the runtime front end alone
#
# The runtime targets deliberately do not depend on the engine targets. Building
# the runtime alone against a stale library is a thing you sometimes want, and
# making it a prerequisite would relink the engine on every front end build. If
# the import library is not there yet the linker says so.
#
# Each target is the entire build in plain commands: build the miniz static
# library, make sure build/ exists, hand the rest to Odin. There is no host
# detection and nothing generated, so when a build fails the commands that ran
# are the ones written below.
#
# The library is a real prerequisite rather than a step, so miniz is only
# recompiled when miniz.c or miniz.h actually change. That matters because it is
# 300KB of C and takes far longer than the Odin build does.
#
# The targets are named rather than detected from the host so that this file
# stays valid for both nmake, which is what Windows has, and GNU make, which is
# what Linux has. Neither has to be installed: nmake ships with the MSVC Build
# Tools and make is on any Linux that can already compile C.
#
# The result is self contained. raylib and box3d are linked as static libraries
# by Odin's vendor bindings and miniz is built static here, so the engine library
# is the only thing a front end has to ship beside its executable. On Windows it
# does import VCRUNTIME140.dll, but that comes from Odin's prebuilt raylib.lib
# and is there with or without miniz.
#
# src/engine builds as a shared library rather than an executable, because it is
# meant to be driven by more than one front end. The front ends live beside it
# as their own packages and each links the library and builds to its own
# executable. src/runtime is the first of them; src/editor is planned.
#
# The link is by import library, not by dlopen, so build/engine.dll and
# build/inky.exe have to sit in the same directory to run. They both build into
# build/ for that reason. On Linux the same is true of build/libengine.so, which
# is why the runtime is linked with an $ORIGIN rpath below: without it the
# loader searches the system paths and never looks next to the executable.

# MINIZ_DISABLE_ZIP_READER_CRC32_CHECKS on both targets because src/engine/pak
# does the CRC itself with core:hash. miniz checks byte at a time, which on a
# pak stored without compression costs about ten times the read it is verifying.
# Removing this define does not disable the check, it just pays for it twice.
#
# /MT because Odin links the static UCRT on Windows. Building this /MD instead
# leaves the CRT imports miniz needs unresolved at link time.
windows: windows-engine windows-runtime

windows-engine: vendor/miniz/miniz.lib
	if not exist build mkdir build
	odin build src/engine -build-mode:dll -out:build/engine.dll

windows-runtime:
	if not exist build mkdir build
	odin build src/runtime -out:build/inky.exe -extra-linker-flags:"/LIBPATH:build"

vendor/miniz/miniz.lib: vendor/miniz/miniz.c vendor/miniz/miniz.h
	cl /nologo /c /O2 /MT /DMINIZ_DISABLE_ZIP_READER_CRC32_CHECKS vendor/miniz/miniz.c /Fo:vendor/miniz/miniz.obj
	lib /nologo /OUT:vendor/miniz/miniz.lib vendor/miniz/miniz.obj

# -fPIC because this object ends up inside libengine.so, and _LARGEFILE64_SOURCE
# because glibc otherwise caps miniz at 2GB archives.
linux: linux-engine linux-runtime

linux-engine: vendor/miniz/libminiz.a
	mkdir -p build
	odin build src/engine -build-mode:dll -out:build/libengine.so

linux-runtime:
	mkdir -p build
	odin build src/runtime -out:build/inky -extra-linker-flags:"-Lbuild -Wl,-rpath,\$$ORIGIN"

vendor/miniz/libminiz.a: vendor/miniz/miniz.c vendor/miniz/miniz.h
	cc -O2 -fPIC -D_LARGEFILE64_SOURCE=1 -DMINIZ_DISABLE_ZIP_READER_CRC32_CHECKS -c vendor/miniz/miniz.c -o vendor/miniz/miniz.o
	ar rcs vendor/miniz/libminiz.a vendor/miniz/miniz.o
