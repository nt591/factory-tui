#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
exec opam exec --switch=. -- dune exec factory-tui -- "$@"
