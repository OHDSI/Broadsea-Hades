#!/bin/bash
# Query P3M API for system requirements of all packages in renv.lock
# Usage: ./get-sysreqs.sh [renv.lock URL or path] [ubuntu-release] [snapshot-date]
# Output: Space-separated list of apt packages needed

set -e

LOCKFILE="${1:-https://raw.githubusercontent.com/OHDSI/Hades/main/hadesWideReleases/2025Q3/renv.lock}"
UBUNTU_RELEASE="${2:-22.04}"
SNAPSHOT_DATE="${3:-${SNAPSHOT_DATE:-}}"
BATCH_SIZE=25
SKIP_SYSREQS_PACKAGES="${SKIP_SYSREQS_PACKAGES:-CohortExplorer}"
P3M_BASE_URL="${P3M_BASE_URL:-https://p3m.dev}"

# Fetch lockfile and extract package names into array (CRAN packages only)
# P3M API only knows about CRAN packages, not GitHub-sourced OHDSI packages
if [[ "$LOCKFILE" == http* ]]; then
    mapfile -t PACKAGES < <(curl -fsSL --retry 3 "$LOCKFILE" | jq -r '.Packages | to_entries[] | select(.value.Repository == "CRAN") | .key')
else
    mapfile -t PACKAGES < <(jq -r '.Packages | to_entries[] | select(.value.Repository == "CRAN") | .key' "$LOCKFILE")
fi

# Filter out skip list packages upfront to avoid unnecessary P3M queries
SKIP_LIST="${SKIP_SYSREQS_PACKAGES//,/ }"
FILTERED_PACKAGES=()
for pkg in "${PACKAGES[@]}"; do
    SKIP=false
    for skip_pkg in $SKIP_LIST; do
        if [ "$pkg" = "$skip_pkg" ]; then
            echo "Skipping $pkg (in SKIP_SYSREQS_PACKAGES)" >&2
            SKIP=true
            break
        fi
    done
    if [ "$SKIP" = false ]; then
        FILTERED_PACKAGES+=("$pkg")
    fi
done
PACKAGES=("${FILTERED_PACKAGES[@]}")

if [ -z "$SNAPSHOT_DATE" ]; then
    SCRIPT_DIR=$(dirname "$0")
    if [ -x "$SCRIPT_DIR/get-lockfile-snapshot-date.sh" ]; then
        SNAPSHOT_DATE=$("$SCRIPT_DIR/get-lockfile-snapshot-date.sh" "$LOCKFILE")
    else
        echo "ERROR: SNAPSHOT_DATE not set and get-lockfile-snapshot-date.sh not found" >&2
        exit 1
    fi
fi

if command -v lsb_release >/dev/null 2>&1; then
    CODENAME=$(lsb_release -cs)
else
    CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
fi

if [ -z "$CODENAME" ]; then
    echo "ERROR: Could not determine Ubuntu codename" >&2
    exit 1
fi

PACKAGES_URL="${P3M_BASE_URL}/cran/__linux__/${CODENAME}/${SNAPSHOT_DATE}/src/contrib/PACKAGES"
if ! curl -fsSL --retry 3 -o /dev/null "$PACKAGES_URL"; then
    EARLIEST_AVAILABLE=$(curl -fsSL --retry 3 "${P3M_BASE_URL}/cran/__linux__/${CODENAME}/" | \
        grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | head -1)
    if [ -z "$EARLIEST_AVAILABLE" ]; then
        EARLIEST_AVAILABLE="unknown"
    fi
    echo "ERROR: P3M snapshot ${SNAPSHOT_DATE} is not available for Ubuntu ${CODENAME}; update SNAPSHOT_DATE to the earliest available date for ${CODENAME} (e.g., ${EARLIEST_AVAILABLE})." >&2
    exit 1
fi

ALL_SYSREQS=""
LAST_API_URL=""

query_sysreqs() {
    local pkgs=("$@")
    local query_params=""
    for pkg in "${pkgs[@]}"; do
        query_params="${query_params}&pkgname=${pkg}"
    done

    LAST_API_URL="${P3M_BASE_URL}/__api__/repos/cran/sysreqs?all=false&distribution=ubuntu&release=${UBUNTU_RELEASE}&snapshot=${SNAPSHOT_DATE}${query_params}"

    if ! RESPONSE=$(curl -fsSL --retry 3 --retry-delay 2 "$LAST_API_URL"); then
        return 1
    fi

    if ! echo "$RESPONSE" | jq -e '.requirements and (.requirements | type == "array")' >/dev/null; then
        return 1
    fi

    echo "$RESPONSE" | jq -r '.requirements[].requirements.packages[]?'
}

process_batch() {
    local pkgs=("$@")
    local output=""

    if output=$(query_sysreqs "${pkgs[@]}"); then
        ALL_SYSREQS="${ALL_SYSREQS}
${output}"
        return 0
    fi

    if [ "${#pkgs[@]}" -le 1 ]; then
        echo "ERROR: Failed to fetch sysreqs from P3M API for package: ${pkgs[0]}" >&2
        echo "URL: $LAST_API_URL" >&2
        echo "This should not happen if skip list is properly configured." >&2
        exit 1
    fi

    echo "WARNING: P3M API failed for batch of ${#pkgs[@]} packages; splitting and retrying..." >&2
    local mid=$(( ${#pkgs[@]} / 2 ))
    local first=("${pkgs[@]:0:mid}")
    local second=("${pkgs[@]:mid}")
    process_batch "${first[@]}"
    process_batch "${second[@]}"
}

# Process in batches to avoid URL length limits
for ((i=0; i<${#PACKAGES[@]}; i+=BATCH_SIZE)); do
    BATCH=("${PACKAGES[@]:i:BATCH_SIZE}")
    process_batch "${BATCH[@]}"
done

# Output unique sorted packages
echo "$ALL_SYSREQS" | sort -u | grep -v '^$' | tr '\n' ' '
echo
