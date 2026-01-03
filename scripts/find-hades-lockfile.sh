#!/bin/bash
# Script to find the renv.lock directory for a given HADES version
# Searches newest directories first for efficiency
# Usage: ./find-hades-lockfile.sh <version>
# Example: ./find-hades-lockfile.sh 1.19.0

set -e

VERSION=$1
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 1.19.0"
  exit 1
fi

echo "Searching for HADES version ${VERSION}..." >&2

# Get list of directories from GitHub API, sorted in reverse (newest first)
# GitHub API returns directories in alphabetical order, so we reverse to check newest first
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

# Check each directory for matching version (newest first)
for dir in $DIRS; do
  echo "Checking $dir..." >&2
  LOCK_VERSION=$(curl -fsSL --retry 3 "https://raw.githubusercontent.com/OHDSI/Hades/main/hadesWideReleases/$dir/renv.lock" | \
                 jq -r '.Packages.Hades.Version // empty' 2>/dev/null)

  if [ "$LOCK_VERSION" = "$VERSION" ]; then
    echo "✓ Found match in $dir" >&2
    echo "$dir"
    exit 0
  fi
done

echo "ERROR: No renv.lock found for HADES version ${VERSION}" >&2
echo "Searched directories (newest to oldest):" >&2
echo "$DIRS" >&2
exit 1
