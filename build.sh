#!/bin/bash
# Wrapper script to build Broadsea-Hades Docker image
# Automatically determines R version from HADES version
# Usage: ./build.sh [hades_version]
# Example: ./build.sh 1.19.0
# Example: ./build.sh (uses latest)
# Environment variables:
#   DOCKER_CACHE_DIR - Directory for Docker build cache (default: /tmp/.buildx-cache)

set -e

# Redirect all output to build.log
LOG_FILE="$(dirname "$0")/build.log"
exec > >(tee "$LOG_FILE") 2>&1
echo "Build started at $(date)"
echo "Logging to: $LOG_FILE"
echo ""

HADES_VERSION=${1:-}
DOCKER_CACHE_DIR=${DOCKER_CACHE_DIR:-/tmp/.buildx-cache}

# Provide GITHUB_TOKEN for helper scripts when running locally
if [ -z "${GITHUB_TOKEN:-}" ] && [ -n "${BUILD_GITHUB_PAT:-}" ]; then
  GITHUB_TOKEN="${BUILD_GITHUB_PAT}"
  export GITHUB_TOKEN
fi

if [ -z "${GITHUB_TOKEN:-}" ] && [ -f "$(dirname "$0")/GITHUBPAT.txt" ]; then
  GITHUB_TOKEN=$(cat "$(dirname "$0")/GITHUBPAT.txt")
  export GITHUB_TOKEN
fi

# Discover HADES version if not specified
if [ -z "$HADES_VERSION" ]; then
  echo "No HADES version specified, discovering latest..."
  HADES_VERSION=$(./scripts/get-latest-hades-version.sh)
  echo "Using latest HADES version: ${HADES_VERSION}"
fi

# Get R version for this HADES release
echo "Determining R version for HADES ${HADES_VERSION}..."
R_VERSION=$(./scripts/get-r-version.sh "${HADES_VERSION}")
echo "R version: ${R_VERSION}"

# Create cache directory if it doesn't exist
mkdir -p "${DOCKER_CACHE_DIR}"

# Build Docker image
echo ""
echo "Building ohdsi/broadsea-hades:${HADES_VERSION}..."
echo "Base image: rocker/rstudio:${R_VERSION}"
echo "Cache directory: ${DOCKER_CACHE_DIR}"
echo ""

# Get current timestamp in ISO 8601 format
BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

# Get git commit SHA if available
GIT_REVISION=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

docker buildx build \
  --pull \
  --build-arg R_VERSION="${R_VERSION}" \
  --build-arg HADES_VERSION="${HADES_VERSION}" \
  --secret id=build_github_pat,src=./GITHUBPAT.txt \
  --label "org.opencontainers.image.created=${BUILD_TIMESTAMP}" \
  --label "org.opencontainers.image.revision=${GIT_REVISION}" \
  --label "org.ohdsi.hades.r.version=${R_VERSION}" \
  --cache-from type=local,src="${DOCKER_CACHE_DIR}" \
  --cache-to type=local,dest="${DOCKER_CACHE_DIR}",mode=max \
  --load \
  -t "ohdsi/broadsea-hades:${HADES_VERSION}" \
  -t "ohdsi/broadsea-hades:latest" \
  .

echo ""
echo "✓ Build complete!"
echo "  Image: ohdsi/broadsea-hades:${HADES_VERSION}"
echo "  Also tagged as: ohdsi/broadsea-hades:latest"
echo ""
echo "Build completed at $(date)"
echo "Full build log saved to: $LOG_FILE"
