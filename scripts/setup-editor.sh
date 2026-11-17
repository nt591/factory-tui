#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
exec opam install --switch="$root" ocaml-lsp-server.1.23.1 ocamlformat.0.29.0 -y
