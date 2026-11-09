#!/usr/bin/env bash
# The packaged zip must hold the TOC, the Lua it lists, Bindings.xml
# (loaded by name, never from the TOC), the sounds (by path) and, when the
# TOC loads it, the embedded LibGlass-1.0 exactly as the library ships it
# (its XML, every file the XML loads, LICENSE, Media/*.tga) at the .pkgmeta
# pin, and nothing else: no ApothecaProbe, no Tools, no library tests or docs.
# Used by the package check and the GitHub release workflow.
# Usage: Tools/check_package.sh <zip>
# The library's checkout is $LIBGLASS, else fetched here at the pin
# (tests/fetch_external.sh), so a backfilled tag checks its own pin.
set -euo pipefail
zip=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unzip -q "$zip" -d "$work/unpacked"
LIBXML='Libs\LibGlass-1.0\LibGlass-1.0.xml'
lib=Libs/LibGlass-1.0
haslib=no
if tr -d '\r' < Apotheca.toc | grep -qxF "$LIBXML"; then haslib=yes; fi
if [ "$haslib" = yes ] && [ -z "${LIBGLASS:-}" ]; then
    bash tests/fetch_external.sh "$lib" "$work/LibGlass"
    LIBGLASS="$work/LibGlass"
fi
# Bindings.xml is expected only where the checkout has it (from 2.6.0):
# backfilling an older tag checks that tag's own files.
{
    echo Apotheca.toc
    if [ -f Bindings.xml ]; then echo Bindings.xml; fi
    if [ -d Sounds ]; then find Sounds -type f; fi
    tr -d '\r' < Apotheca.toc | grep -v '^#' | sed '/^$/d' | grep -vxF "$LIBXML" | tr '\\' '/'
    if [ "$haslib" = yes ]; then
        echo "$lib/LibGlass-1.0.xml"
        echo "$lib/LICENSE"
        # Comments stripped non-greedily (a file listed in a comment isn't loaded).
        tr -d '\r' < "$LIBGLASS/LibGlass-1.0.xml" | perl -0pe 's/<!--.*?-->//gs' |
            sed -n 's/.*<Script file="\([^"]*\)".*/\1/p' | tr '\\' '/' | sed "s|^|$lib/|"
        (cd "$LIBGLASS" && ls Media/*.tga) | sed "s|^|$lib/|"
    fi
} | sort > "$work/expected.txt"
(cd "$work/unpacked/Apotheca" && find . -type f | sed 's|^\./||' | sort) > "$work/actual.txt"
diff -u "$work/expected.txt" "$work/actual.txt"
extra=$(cd "$work/unpacked" && find . -mindepth 1 -maxdepth 1 ! -name Apotheca)
test -z "$extra" || { echo "zip has entries outside Apotheca/: $extra"; exit 1; }
# The packager fetched its own copy of the library: it must be the pinned
# commit's content. Its text filter rewrites .lua/.xml with CRLF, so those
# compare with CRs stripped; textures and LICENSE byte for byte.
if [ "$haslib" = yes ]; then
    bad=0
    while read -r f; do
        rel=${f#"$lib/"}
        case "$rel" in
            *.lua|*.xml) cmp -s <(tr -d '\r' < "$work/unpacked/Apotheca/$f") <(tr -d '\r' < "$LIBGLASS/$rel") ;;
            *) cmp -s "$work/unpacked/Apotheca/$f" "$LIBGLASS/$rel" ;;
        esac || { echo "LibGlass-1.0 differs from the pinned checkout: $rel"; bad=1; }
    done < <(grep "^$lib/" "$work/expected.txt")
    test "$bad" -eq 0
fi
echo "package ok: $zip"
