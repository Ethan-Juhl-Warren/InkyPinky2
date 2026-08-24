# Builds the engine, and the vendored miniz C library that src/pak links against.
#
#   Linux     make linux
#   Windows   nmake windows     (from a Developer Command Prompt, so cl is on PATH)
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
# The result is standalone. raylib and box3d are linked as static libraries by
# Odin's vendor bindings and miniz is built static here, so nothing has to sit
# beside the executable. On Windows it does import VCRUNTIME140.dll, but that
# comes from Odin's prebuilt raylib.lib and is there with or without miniz.

# MINIZ_DISABLE_ZIP_READER_CRC32_CHECKS on both targets because src/pak does the
# CRC itself with core:hash. miniz checks byte at a time, which on a pak stored
# without compression costs about ten times the read it is verifying. Removing
# this define does not disable the check, it just pays for it twice.
#
# /MT because Odin links the static UCRT on Windows. Building this /MD instead
# leaves the CRT imports miniz needs unresolved at link time.
windows: vendor/miniz/miniz.lib
	if not exist build mkdir build
	odin build src -out:build/inky.exe

vendor/miniz/miniz.lib: vendor/miniz/miniz.c vendor/miniz/miniz.h
	cl /nologo /c /O2 /MT /DMINIZ_DISABLE_ZIP_READER_CRC32_CHECKS vendor/miniz/miniz.c /Fo:vendor/miniz/miniz.obj
	lib /nologo /OUT:vendor/miniz/miniz.lib vendor/miniz/miniz.obj

# -fPIC because distributions default to PIE executables, and _LARGEFILE64_SOURCE
# because glibc otherwise caps miniz at 2GB archives.
linux: vendor/miniz/libminiz.a
	mkdir -p build
	odin build src -out:build/inky

vendor/miniz/libminiz.a: vendor/miniz/miniz.c vendor/miniz/miniz.h
	cc -O2 -fPIC -D_LARGEFILE64_SOURCE=1 -DMINIZ_DISABLE_ZIP_READER_CRC32_CHECKS -c vendor/miniz/miniz.c -o vendor/miniz/miniz.o
	ar rcs vendor/miniz/libminiz.a vendor/miniz/miniz.o
