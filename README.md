# Broadsea-Hades

OHDSI/Broadsea-Hades Docker container with Rocker RStudio Server and OHDSI HADES

## Quick Start

### Run Pre-Built Image

```bash
# Run latest version from Docker Hub
docker-compose up -d

# Access RStudio at http://localhost:8787
# Username: rstudio, Password: mypass
```

### Optional local build

**Prerequisites:**

```bash

# OS
ubuntu

# Create a buildx builder with docker-container driver (one-time setup)
docker buildx create --name builder-with-local-cache --driver docker-container --use

# The helper scripts require the tools: curl and jq

```

**Optional Local Build steps:**

```bash
# 1. Provide a GitHub PAT (REQUIRED in local build to avoid GitHub API rate limits)
# File-based (required for the Buildx secret and helper scripts; remove the file after the build)
old_umask=$(umask)
umask 077
read -s -p "GitHub PAT: " PAT; echo
printf '%s\n' "$PAT" > GITHUBPAT.txt
unset PAT
umask "$old_umask"

# 2. Build latest released HADES version
./build.sh

# 3. Build specific HADES version (in this example v1.19.0)
./build.sh 1.19.0

# 4. Run the container (local build does not push to Docker Hub)
docker-compose up -d
```

#### Optional: Configure cache directory to speed up local builds

```bash
# Set custom cache location (default: /tmp/.buildx-cache)
export DOCKER_CACHE_DIR=/home/me/.buildx-cache
```

## Features

- **Automatic Version Detection**: Automatically finds and uses the latest HADES release
- **Faster Binary Installations**: Uses Posit Public Package Manager (P3M) snapshot for pre-compiled CRAN packages
- **Build Docker Image from HADES renv.lock file**: Uses the renv.lock file associated with each HADES release
- **Daily Automated Builds**: GitHub Action polls daily for new HADES releases

## Build Scripts

- `build.sh` - local build script
- `scripts/get-latest-hades-version.sh` - Find latest HADES version
- `scripts/get-r-version.sh` - Extract R version from renv.lock
- `scripts/find-hades-lockfile.sh` - Find renv.lock directory for version
- `scripts/get-lockfile-snapshot-date.sh` - Get P3M snapshot date from renv.lock commit

## Verification

Check the HADES version in a running container:

```bash
docker run --rm ohdsi/broadsea-hades:latest R -e "packageVersion('Hades')"
```

Inspect image metadata:

```bash
docker inspect ohdsi/broadsea-hades:latest | jq '.[0].Config.Labels."org.opencontainers.image.version"'
```

## GitHub Actions

Two automated workflows:

1. **Manual/Tag Builds** (`.github/workflows/docker-publish.yml`)
   - Trigger: Push tag `v1.19.0` or click "Run workflow"
   - Publishes to Docker Hub: `ohdsi/broadsea-hades`

2. **Daily Auto-Build** (`.github/workflows/daily-check-and-publish.yml`)
   - Runs daily at 2 AM UTC
   - Automatically builds new docker image for new HADES release (when there is a new renv lock file)
   - Skips build if docker image already exists in Docker Hub

**Local build (build.sh) GitHub PAT**

- Create `GITHUBPAT.txt` with a GitHub PAT; `build.sh` passes this into Buildx as `--secret id=build_github_pat,src=./GITHUBPAT.txt`, so the file is required for the Docker build step and to authenticate the helper scripts.

**GitHub Actions Secrets**

- The below secrets need to be set in your GitHub repository or GitHub organization (Settings → Secrets and variables → Actions):
  - `DOCKER_HUB_USERNAME` - Your Docker Hub username
  - `DOCKER_HUB_ACCESS_TOKEN` - Docker Hub access token ([create here](https://hub.docker.com/settings/security))
  - `GH_TOKEN` - GitHub PAT passed into the Docker build as a Buildx secret (`build_github_pat`) to avoid GitHub API rate limits inside the Dockerfile
- Workflow steps that call helper scripts use the built-in `github.token` and do not require a PAT.
