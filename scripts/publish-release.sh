#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
: "${RELEASE_TAG:?Set RELEASE_TAG to the version tag}"
: "${GH_REPO:?Set GH_REPO to owner/repository}"
python3 scripts/check-project.py --release-tag "$RELEASE_TAG"
NOTES="docs/releases/$RELEASE_TAG.md"

if draft="$(gh release view "$RELEASE_TAG" --json isDraft --jq .isDraft 2>/dev/null)"; then
    if [[ "$draft" != "true" ]]; then
        echo "$RELEASE_TAG is already published; its assets will not be changed."
        exit 0
    fi
    gh release edit "$RELEASE_TAG" --title "Speaker Timer $RELEASE_TAG" --notes-file "$NOTES"
else
    gh release create "$RELEASE_TAG" --verify-tag --draft --title "Speaker Timer $RELEASE_TAG" --notes-file "$NOTES"
fi

gh release upload "$RELEASE_TAG" dist/*.dmg dist/*.zip dist/SHA256SUMS --clobber
gh release edit "$RELEASE_TAG" --draft=false
