#!/bin/sh
# Builds and runs the engine.
#
# The Linux side of the Makefile only needs cc and ar, which are already on PATH
# on any machine that can compile C, so this is just the Makefile plus the run.
# miniz is only recompiled when its source changes, so a normal run is just the
# Odin build.
#
#   ./run.sh           build and run
#   ./run.sh --build   build only

set -e

build_only=""
case "$1" in
	"") ;;
	--build|-Build) build_only=1 ;;
	*) echo "usage: $0 [--build]" >&2; exit 2 ;;
esac

make linux

if [ -z "$build_only" ]; then
	exec ./build/inky
fi
