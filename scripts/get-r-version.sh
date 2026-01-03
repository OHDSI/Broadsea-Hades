#!/bin/bash
# Script to extract R version from a HADES renv.lock file
# Usage: ./get-r-version.sh <hades_version>
# Example: ./get-r-version.sh 1.19.0
# Returns: R version in format like "4.4.1"

set -e

HADES_VERSION=$1
if [ -z "$HADES_VERSION" ]; then
  echo "Usage: $0 <hades_version>"
  echo "Example: $0 1.19.0"
  exit 1
fi

# Find the lockfile directory for this HADES version
SCRIPT_DIR=$(dirname "$0")
LOCK_DIR=$("$SCRIPT_DIR/find-hades-lockfile.sh" "$HADES_VERSION")

if [ -z "$LOCK_DIR" ]; then
  echo "ERROR: Could not find renv.lock for HADES version ${HADES_VERSION}" >&2
  exit 1
fi

echo "Fetching R version from ${LOCK_DIR}/renv.lock..." >&2

# Download and extract R version from renv.lock
R_VERSION=$(curl -fsSL --retry 3 "https://raw.githubusercontent.com/OHDSI/Hades/main/hadesWideReleases/$LOCK_DIR/renv.lock" | \
            jq -r '.R.Version // empty')

if [ -z "$R_VERSION" ]; then
  echo "ERROR: Could not extract R version from renv.lock" >&2
  exit 1
fi

echo "R version: ${R_VERSION}" >&2
echo "$R_VERSION"
