#!/bin/bash
# Determine the P3M snapshot date for a HADES renv.lock file
# Usage: ./get-lockfile-snapshot-date.sh <renv.lock URL>
# Environment:
#   SNAPSHOT_DATE - optional override

set -e

LOCKFILE=$1
if [ -z "$LOCKFILE" ]; then
  echo "Usage: $0 <renv.lock URL>" >&2
  exit 1
fi

if [ -n "${SNAPSHOT_DATE:-}" ]; then
  echo "$SNAPSHOT_DATE"
  exit 0
fi

if [[ "$LOCKFILE" != http* ]]; then
  echo "ERROR: lockfile is a local path; set SNAPSHOT_DATE explicitly" >&2
  exit 1
fi

if [[ "$LOCKFILE" =~ ^https://raw\.githubusercontent\.com/OHDSI/Hades/([^/]+)/(.+)$ ]]; then
  REF="${BASH_REMATCH[1]}"
  PATH_PART="${BASH_REMATCH[2]}"
else
  echo "ERROR: Unsupported lockfile URL format: $LOCKFILE" >&2
  exit 1
fi

if [[ "$PATH_PART" != hadesWideReleases/*/renv.lock ]]; then
  echo "ERROR: Unsupported lockfile path: $PATH_PART" >&2
  exit 1
fi

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

API_URL="https://api.github.com/repos/OHDSI/Hades/commits?path=${PATH_PART}&sha=${REF}&per_page=1"
RESPONSE=$(curl -fsSL --retry 3 "${CURL_OPTS[@]}" "$API_URL")
SNAPSHOT_DATE=$(echo "$RESPONSE" | jq -r '.[0].commit.committer.date // empty' | cut -dT -f1)

if [ -z "$SNAPSHOT_DATE" ]; then
  echo "ERROR: Could not determine snapshot date from GitHub API" >&2
  echo "URL: $API_URL" >&2
  exit 1
fi

echo "$SNAPSHOT_DATE"
