#!/bin/bash
# Script to find the latest HADES version from hadesWideReleases
# Returns the version number of the most recent release
# Usage: ./get-latest-hades-version.sh

set -e

# Get list of directories from GitHub API, sorted in reverse (newest first)
CURL_CFG=""
cleanup() {
  if [ -n "$CURL_CFG" ]; then
    rm -f "$CURL_CFG"
  fi
}
trap cleanup EXIT

TOKEN="${GITHUB_TOKEN:-}"
if [ -n "$TOKEN" ]; then
  CURL_CFG=$(mktemp)
  chmod 600 "$CURL_CFG"
  printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" > "$CURL_CFG"
  printf 'header = "Accept: application/vnd.github+json"\n' >> "$CURL_CFG"
  printf 'header = "X-GitHub-Api-Version: 2022-11-28"\n' >> "$CURL_CFG"
fi

if [ -n "$CURL_CFG" ]; then
  CURL_OPTS=(--config "$CURL_CFG")
else
  CURL_OPTS=()
fi

DIRS=$(curl -fsSL --retry 3 "${CURL_OPTS[@]}" https://api.github.com/repos/OHDSI/Hades/contents/hadesWideReleases | \
       jq -r '.[].name' | sort -r)

# Check directories in order (newest first) until we find one with a valid version
for dir in $DIRS; do
  VERSION=$(curl -fsSL --retry 3 "https://raw.githubusercontent.com/OHDSI/Hades/main/hadesWideReleases/$dir/renv.lock" | \
            jq -r '.Packages.Hades.Version // empty' 2>/dev/null)

  if [ -n "$VERSION" ]; then
    echo "$VERSION"
    exit 0
  fi
done

# Error if no version found
echo "ERROR: Could not find any HADES version in hadesWideReleases" >&2
exit 1
