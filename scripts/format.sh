#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
case "${1:-}" in
  "") exec opam exec --switch="$root" -- dune fmt ;;
  --check) exec opam exec --switch="$root" -- dune build @fmt ;;
  *) printf '%s\n' 'Usage: scripts/format.sh [--check]' >&2; exit 2 ;;
esac
