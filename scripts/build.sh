#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
switch=${FACTORY_OPAM_SWITCH:-$root}
build_dir=${FACTORY_BUILD_DIR:-$root/_build}
case "$build_dir" in /*) ;; *) build_dir="$root/$build_dir" ;; esac
if [ "$#" -eq 0 ]; then set -- @install; fi
exec opam exec --switch="$switch" -- dune build --root "$root" --build-dir "$build_dir" "$@"
