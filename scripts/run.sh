#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
opam exec --switch="$root" -- dune build --root "$root" @install
exec opam exec --switch="$root" -- "$root/_build/default/bin/main.exe" "$@"
