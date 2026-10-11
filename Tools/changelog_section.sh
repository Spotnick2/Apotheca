#!/usr/bin/env bash
# Print one version's section of CHANGELOG.md (without its heading), for the
# GitHub release notes. Fails if the version has no section: every tag needs
# its entry committed before the tag (AGENTS.md, Releasing).
# Usage: Tools/changelog_section.sh 2.6.0
set -euo pipefail
version=$1
tr -d '\r' < CHANGELOG.md | awk -v v="$version" '
    index($0, "## [" v "]") == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
    END { if (!found) { print "CHANGELOG.md has no section for " v > "/dev/stderr"; exit 1 } }
' | sed -e '/./,$!d'
