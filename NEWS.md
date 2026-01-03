Broadsea-Hades
==============

Initial 2026 release of automated build action for Broadsea-Hades Docker image.

- Automated HADES release version discovery and docker image build system
- Docker image version tag now set to the HADES release number (previously it used R version number)
- Docker image base image rocker/rstudio aligned to HADES renv.lock R version
- All HADES R packages installed from exact versions in renv.lock file
- All HADES CRAN R packages installed as binaries from Posit Public Package Manager (P3M)
- Automatic OS security updates applied to base image OS packages in build
- `--pull` flag ensures latest rocker/rstudio base image is used in build
- OCI-compliant docker image labels
- Optimized layer caching for faster rebuilds
- Secure handling of GitHub PAT via Docker secrets for Docker build steps (Actions script steps use GitHub's built-in token)
- Docker image tagged with HADES version (e.g. ohdsi/broadsea-hades:1.19.0) and 'latest' tag
- RStudio Server accessible on port 8787
- Rserve support for R execution (port 6311)
- All JDBC drivers pre-installed for database connectivity
- OpenJDK 11 installed for Java-dependent packages
- Python 3 virtual environment via reticulate
- supervisord for process management

Build Infrastructure
---------------------

- Automatic R version detection from HADES renv.lock files
- Base image tag `rocker/rstudio:<R_VERSION>` is aligned to the R version from renv.lock
- Posit Public Package Manager (P3M) snapshot date computed from renv.lock commit & reused for `renv::restore` to align R package binaries
- Helper scripts:
  - `scripts/get-latest-hades-version.sh`
  - `scripts/find-hades-lockfile.sh`
  - `scripts/get-r-version.sh`
  - `scripts/get-lockfile-snapshot-date.sh`
  - `scripts/get-sysreqs.sh`
- System dependencies for CRAN packages are derived via P3M sysreqs snapshot matching renv.lock commit date
- (override CRAN binaries skip list with `SKIP_SYSREQS_PACKAGES=""`)
- GitHub-only HADES packages list no SystemRequirements beyond Java; Java and Python tooling are included in the image
- Added `build.sh` wrapper script for optional local builds with automatic HADES version detection
- Local BuildKit cache support for faster optional local rebuilds

GitHub Actions Workflows
-------------------------

- Automatic builds published to Docker Hub as `ohdsi/broadsea-hades:<version>` and `ohdsi/broadsea-hades:latest`
- `daily-check-and-publish.yml`: Automated daily check and new docker image build for new HADES releases
- `docker-publish.yml`: Build and publish images on git tag push or manual trigger
