#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
switch=${FACTORY_OPAM_SWITCH:-$root}
build_dir=${FACTORY_BUILD_DIR:-$root/_build}
"$root/scripts/build.sh" @install
opam exec --switch="$switch" -- dune runtest --root "$root" --build-dir "$build_dir" --force
