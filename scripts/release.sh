#!/usr/bin/env bash
# Membuat artefak rilis universal dan (opsional) mengunggahnya ke GitHub Releases.
# Pemakaian: scripts/release.sh X.Y.Z [--publish]
set -euo pipefail

VERSION="${1:?Pemakaian: scripts/release.sh X.Y.Z [--publish]}"
VERSION="${VERSION#v}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/scripts/build-app.sh" "$VERSION"

if [ "${2:-}" = "--publish" ]; then
    command -v gh >/dev/null || { echo "Perlu GitHub CLI (gh) untuk --publish."; exit 1; }
    NAME="DeskWidgets-v${VERSION}-macos-universal"
    gh release create "v${VERSION}" \
        "$ROOT/dist/$NAME.zip" "$ROOT/dist/$NAME.zip.sha256" \
        --title "DeskWidgets v${VERSION}" --generate-notes
fi
