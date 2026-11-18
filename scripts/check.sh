#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
switch=${FACTORY_OPAM_SWITCH:-$root}
build_dir=${FACTORY_BUILD_DIR:-$root/_build}
case "$build_dir" in /*) ;; *) build_dir="$root/$build_dir" ;; esac
"$root/scripts/build.sh" @install
opam exec --switch="$switch" -- dune runtest --root "$root" --build-dir "$build_dir" --force

python3 "$root/scripts/test-responses.py"
