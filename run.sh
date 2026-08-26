#!/bin/sh
# Builds and runs the engine.
#
# The Linux side of the Makefile only needs cc and ar, which are already on PATH
# on any machine that can compile C, so this is just the Makefile plus the run.
# miniz is only recompiled when its source changes, so a normal run is just the
# Odin build.
#
# The engine is a shared library and the runtime is the front end executable
# that links it. Both are built by default. --engine and --runtime narrow that
# to one half, which is worth doing when you are only touching one of them: the
# engine link is the slow one.
#
#   ./run.sh                     build both and run
#   ./run.sh --build             build both
#   ./run.sh --engine            build build/libengine.so only
#   ./run.sh --runtime           build build/inky only
#   ./run.sh --runtime --build   build the runtime without running it
#
# Passing both --engine and --runtime is the same as passing neither. Nothing is
# run when the runtime was not part of the build, since there would be no point
# launching an executable this invocation did not produce.

set -e

engine=""
runtime=""
build_only=""

while [ $# -gt 0 ]; do
	case "$1" in
		--engine|-Engine) engine=1 ;;
		--runtime|-Runtime) runtime=1 ;;
		--build|-Build) build_only=1 ;;
		*) echo "usage: $0 [--engine] [--runtime] [--build]" >&2; exit 2 ;;
	esac
	shift
done

if [ -z "$engine" ] && [ -z "$runtime" ]; then
	engine=1
	runtime=1
fi

if [ -n "$engine" ] && [ -n "$runtime" ]; then
	target=linux
elif [ -n "$engine" ]; then
	target=linux-engine
else
	target=linux-runtime
fi

make "$target"

if [ -z "$build_only" ] && [ -n "$runtime" ]; then
	exec ./build/inky
fi
