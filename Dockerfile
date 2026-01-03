# syntax=docker/dockerfile:1

# Global build arguments (can be overridden at build time)
# Use build.sh wrapper script or github actions for automatic version detection
# Or pass manually: docker build --build-arg R_VERSION=4.4.1 --build-arg HADES_VERSION=1.19.0
ARG R_VERSION
ARG HADES_VERSION

FROM rocker/rstudio:${R_VERSION:-latest}

# Re-declare build args after FROM so they are in-scope for this stage (LABEL/RUN/etc)
ARG R_VERSION
ARG HADES_VERSION

# Apply security updates to rocker base image OS packages
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Metadata labels (following OCI image spec)
LABEL org.opencontainers.image.authors="Lee Evans <evans@ohdsi.org>" \
      org.opencontainers.image.vendor="OHDSI" \
      org.opencontainers.image.title="Broadsea HADES" \
      org.opencontainers.image.description="OHDSI HADES R packages in RStudio" \
      org.opencontainers.image.source="https://github.com/OHDSI/Broadsea-Hades" \
      org.opencontainers.image.url="https://github.com/OHDSI/Broadsea-Hades" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${HADES_VERSION}"

# Set environment variables
ENV DATABASECONNECTOR_JAR_FOLDER="/opt/hades/jdbc_drivers" \
    WORKON_HOME="/opt/.virtualenvs"

# Install bootstrap OS dependencies (minimal set needed to run get-sysreqs.sh and basic build)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Copy scripts early
COPY Rserv.conf /etc/Rserv.conf
COPY startRserve.R /usr/local/bin/startRserve.R
COPY scripts/find-hades-lockfile.sh /usr/local/bin/find-hades-lockfile.sh
COPY scripts/get-latest-hades-version.sh /usr/local/bin/get-latest-hades-version.sh
COPY scripts/get-lockfile-snapshot-date.sh /usr/local/bin/get-lockfile-snapshot-date.sh
COPY scripts/get-sysreqs.sh /usr/local/bin/get-sysreqs.sh
RUN chmod +x /usr/local/bin/startRserve.R \
             /usr/local/bin/find-hades-lockfile.sh \
             /usr/local/bin/get-latest-hades-version.sh \
             /usr/local/bin/get-lockfile-snapshot-date.sh \
             /usr/local/bin/get-sysreqs.sh

# Dynamically install R package system dependencies from P3M API
# This queries P3M for all packages in renv.lock and installs their OS deps
RUN --mount=type=secret,id=build_github_pat \
    if [ -f /run/secrets/build_github_pat ]; then \
         GITHUB_TOKEN=$(cat /run/secrets/build_github_pat); \
         export GITHUB_TOKEN; \
       fi \
    && if [ -z "${HADES_VERSION}" ] || [ "${HADES_VERSION}" = "unknown" ]; then \
         HADES_VERSION=$(get-latest-hades-version.sh); \
       fi \
    && LOCK_DIR=$(find-hades-lockfile.sh ${HADES_VERSION}) \
    && LOCK_URL="https://raw.githubusercontent.com/OHDSI/Hades/main/hadesWideReleases/$LOCK_DIR/renv.lock" \
    && UBUNTU_RELEASE=$(lsb_release -rs) \
    && SNAPSHOT_DATE=$(get-lockfile-snapshot-date.sh "$LOCK_URL") \
    && echo "Fetching system requirements for R packages from P3M API..." \
    && echo "Using lockfile: $LOCK_URL" \
    && echo "Ubuntu release: $UBUNTU_RELEASE" \
    && echo "Using P3M snapshot date: $SNAPSHOT_DATE" \
    && SYSREQS=$(get-sysreqs.sh "$LOCK_URL" "$UBUNTU_RELEASE" "$SNAPSHOT_DATE") \
    && echo "Installing system dependencies: $SYSREQS" \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       openjdk-11-jdk \
       python3-dev \
       python3-venv \
       python3-pip \
       supervisor \
       $SYSREQS \
    && R CMD javareconf \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install renv package
RUN install2.r --error --skipinstalled renv \
    && rm -rf /tmp/download_packages/ /tmp/*.rds

# Install OHDSI HADES R packages using renv.lock from hadesWideReleases
RUN --mount=type=secret,id=build_github_pat \
    cp /usr/local/lib/R/etc/Renviron /tmp/Renviron \
    && if [ -f /run/secrets/build_github_pat ]; then \
         GITHUB_TOKEN=$(cat /run/secrets/build_github_pat); \
         export GITHUB_TOKEN; \
       fi \
    && echo "GITHUB_PAT=$(cat /run/secrets/build_github_pat)" >> /usr/local/lib/R/etc/Renviron \
    && if [ -z "${HADES_VERSION}" ] || [ "${HADES_VERSION}" = "unknown" ]; then \
         echo "No HADES_VERSION specified, discovering latest version..."; \
         HADES_VERSION=$(get-latest-hades-version.sh); \
         echo "Using latest HADES version: ${HADES_VERSION}"; \
       fi \
    && LOCK_DIR=$(find-hades-lockfile.sh ${HADES_VERSION}) \
    && echo "Found HADES ${HADES_VERSION} in directory: $LOCK_DIR" \
    && LOCK_URL="https://raw.githubusercontent.com/OHDSI/Hades/main/hadesWideReleases/$LOCK_DIR/renv.lock" \
    && SNAPSHOT_DATE=$(get-lockfile-snapshot-date.sh "$LOCK_URL") \
    && echo "Using P3M snapshot date: $SNAPSHOT_DATE" \
    && curl -fsSL --retry 3 -o /tmp/renv.lock "$LOCK_URL" \
    && echo "Restoring R packages from renv.lock using P3M binaries..." \
    && cd /tmp && R -e " \
        options(renv.config.install.verbose = TRUE); \
        options(renv.config.install.transactional = FALSE); \
        ubuntu_version <- system('lsb_release -cs', intern = TRUE); \
        p3m_url <- paste0('https://p3m.dev/cran/__linux__/', ubuntu_version, '/${SNAPSHOT_DATE}'); \
        cat('Using P3M repository:', p3m_url, '\n'); \
        options(repos = c(CRAN = p3m_url)); \
        options(renv.config.repos.override = p3m_url); \
        options(HTTPUserAgent = sprintf('R/%s R (%s)', getRversion(), paste(getRversion(), R.version['platform'], R.version['arch'], R.version['os']))); \
        options(download.file.extra = sprintf('--header \"User-Agent: R (%s)\"', paste(getRversion(), R.version['platform'], R.version['arch'], R.version['os']))); \
        renv::restore(lockfile = '/tmp/renv.lock', library = .libPaths()[1])" \
    && cp /tmp/Renviron /usr/local/lib/R/etc/Renviron \
    && rm -rf /tmp/download_packages/ /tmp/*.rds /tmp/renv.lock

# Download JDBC drivers for all supported database platforms
RUN R -e "library(DatabaseConnector); downloadJdbcDrivers('all')"

# Install Rserve server and client (not in renv.lock)
# docopt is required by startRserve.R script
RUN install2.r --error --skipinstalled \
    docopt \
    Rserve \
    RSclient \
    && rm -rf /tmp/download_packages/ /tmp/*.rds

# Create Python virtual environment for PatientLevelPrediction
RUN R <<EOF
reticulate::use_python("/usr/bin/python3", required=TRUE)
PatientLevelPrediction::configurePython(envname='r-reticulate', envtype='python')
reticulate::use_virtualenv("/opt/.virtualenvs/r-reticulate")
EOF

# Configure supervisor for process management
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE 8787 6311

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
