#!/usr/bin/env bash
# Packs a built Studio as a release has it, the tarball get.sh downloads.
#
#   ./package.sh <binary> <arch> <out folder>    writes <out>/omarchy-macos-studio-<arch>.tar.gz
set -euo pipefail

repo="$(cd "$(dirname "$0")" && pwd)"
binary=$1 arch=$2 out=$3
id=omarchy-macos-studio

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/$id/assets" "$out"
cp "$binary" "$stage/$id/$id"
cp "$repo/install-desktop.sh" "$repo/LICENSE" "$stage/$id/"
cp "$repo/assets/icon-omarchy.svg" "$stage/$id/assets/"
tar -czf "$out/$id-$arch.tar.gz" -C "$stage" "$id"
