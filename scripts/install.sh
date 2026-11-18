#!/bin/sh
set -eu
if [ "$#" -ne 2 ] || [ "$1" != "--prefix" ]; then
  printf '%s\n' 'Usage: scripts/install.sh --prefix /absolute/install/prefix' >&2
  exit 2
fi
case "$2" in /*) ;; *) printf '%s\n' 'Prefix must be absolute.' >&2; exit 2 ;; esac
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
build_dir=${FACTORY_BUILD_DIR:-$root/_build}
case "$build_dir" in /*) ;; *) build_dir="$root/$build_dir" ;; esac
"$root/scripts/build.sh" @install
mkdir -p "$2/bin"
if [ -e "$2/bin/factory-tui" ] || [ -L "$2/bin/factory-tui" ]; then
  printf '%s\n' 'Existing binary refused. Move it aside explicitly before reinstalling.' >&2
  exit 2
fi
staged=$(mktemp "$2/bin/.factory-tui.XXXXXX")
trap 'unlink "$staged"' EXIT HUP INT TERM
cp "$build_dir/default/bin/main.exe" "$staged"
chmod 755 "$staged"
ln "$staged" "$2/bin/factory-tui"
printf '%s\n' "Installed $2/bin/factory-tui. No config or shell files were modified."
