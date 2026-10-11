#!/usr/bin/env bash
# The packaged zip must hold the TOC, the Lua it lists and Bindings.xml
# (loaded by name, never from the TOC), and nothing else: no ApothecaProbe,
# no Tools. Used by the package check and the GitHub release workflow.
# Usage: Tools/check_package.sh <zip>
set -euo pipefail
zip=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unzip -q "$zip" -d "$work/unpacked"
# Bindings.xml is expected only where the checkout has it (from 2.6.0):
# backfilling an older tag checks that tag's own files.
{ echo Apotheca.toc; if [ -f Bindings.xml ]; then echo Bindings.xml; fi; grep -v '^#' Apotheca.toc | tr -d '\r' | sed '/^$/d'; } | sort > "$work/expected.txt"
(cd "$work/unpacked/Apotheca" && find . -type f | sed 's|^\./||' | sort) > "$work/actual.txt"
diff -u "$work/expected.txt" "$work/actual.txt"
extra=$(cd "$work/unpacked" && find . -mindepth 1 -maxdepth 1 ! -name Apotheca)
test -z "$extra" || { echo "zip has entries outside Apotheca/: $extra"; exit 1; }
echo "package ok: $zip"
