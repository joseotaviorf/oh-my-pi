# syntax=docker/dockerfile:1.10
#
# All container images for bi-etl-ejuice in a single multi-stage Dockerfile.
#
# Targets (build with `docker build --target <name>`):
#
#   ci-base          — python:3.12-slim-bookworm + git, make, rsync + uv +
#                      workspace venv at /opt/bietlejuice/venvs/workspace
#                      (core + airflow + compiler).
#                      Used by lint, validation, and release CI steps.
#
#   ci-jdk           — ci-base + openjdk-17-jre-headless +
#                      dbr-16-4 venv at /opt/bietlejuice/venvs/dbr-16-4.
#                      Used by test CI steps (PySpark needs a JVM).
#
#   devcontainer     — ci-jdk + runtime venv at /opt/bietlejuice/venvs/runtime +
#                      dev tooling (vscode user, sudo, zsh, Starship prompt, gh,
#                      AWS CLI v2, Databricks CLI, yq, jq, ripgrep, astro-cli,
#                      weep, woodpecker-cli, QLI).
#                      Inherits workspace + dbr-16-4 from ci-jdk; adds runtime.
#
# Why slim-bookworm?
#   The full python:3.12-bookworm image (~1 GB) inherits the entire
#   buildpack-deps toolchain (gcc, g++, autoconf, dozens of -dev headers).
#   None of our Python dependencies require on-the-fly C compilation — every
#   native package (pandas, pyarrow, grpcio, cryptography, spacy, …) ships
#   pre-built cp312-manylinux wheels. slim-bookworm gives us the same
#   PGO+LTO-optimized CPython binary at ~150 MB without the dead weight.
#
# Venvs are pre-installed at build time into /opt/bietlejuice/venvs/ so they
# live OUTSIDE the /workspaces/bi-etl-ejuice/ bind-mount. post-create.sh
# and CI setup steps run `uv sync` to re-link editable workspace packages
# from the actual checkout path (~1-2s, no wheel downloads). The image is the
# cache; `uv sync` is the source of truth.
#
# Build locally:
#   make build-ci-container-base   # → bi-etl-ejuice-ci:base-latest
#   make build-ci-container-jdk    # → bi-etl-ejuice-ci:jdk-latest
#   make build-devcontainer        # → bi-etl-ejuice:devcontainer-latest
#
# All targets are multi-arch (amd64 + arm64). Use PLATFORM=linux/arm64 with
# the Makefile targets for cross-arch local builds.

ARG UV_VERSION=0.11.7
ARG ASTRO_CLI_VERSION=1.42.0
ARG YQ_VERSION=4.53.2
ARG AWSCLI_VERSION=2.34.47
ARG DATABRICKS_CLI_VERSION=0.299.2
ARG STARSHIP_VERSION=1.25.1
ARG WEEP_VERSION=0.3.31
ARG WOODPECKER_CLI_VERSION=3.14.1

###############################################################################
# Stage: uv-bin — pin the uv binary via a named stage so COPY --from works.
###############################################################################
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv-bin

###############################################################################
# Target: ci-base — Python 3.12 + git + make + rsync + uv + workspace venv
###############################################################################
FROM python:3.12-slim-bookworm AS ci-base

COPY --from=uv-bin /uv /uvx /usr/local/bin/

RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends \
  git \
  make \
  rsync \
  && rm -rf /var/lib/apt/lists/*

# Kaniko and BuildKit execute RUN via SHELL; use bash (not dash) for secret/token handling.
SHELL ["/bin/bash", "-c"]

# Pre-install the workspace venv (core + airflow + compiler) at build time.
# Only pyproject.toml + uv.lock are COPYed (no src/), so this layer is only
# invalidated by dependency changes, not source changes.
# --no-editable: workspace members are installed as regular wheels so no paths
# point into /tmp/workspace. CI setup steps re-run `uv sync` (editable) to
# re-link from the actual checkout path (~1-2s, no wheel downloads).
ENV UV_PROJECT_ENVIRONMENT=/opt/bietlejuice/venvs/workspace

COPY pyproject.toml uv.lock /tmp/workspace/
COPY packages/bietlejuice-core/pyproject.toml /tmp/workspace/packages/bietlejuice-core/pyproject.toml
COPY packages/bietlejuice-airflow/pyproject.toml /tmp/workspace/packages/bietlejuice-airflow/pyproject.toml
COPY packages/bietlejuice-compiler/pyproject.toml /tmp/workspace/packages/bietlejuice-compiler/pyproject.toml
COPY packages/bietlejuice-runtime/pyproject.toml /tmp/workspace/packages/bietlejuice-runtime/pyproject.toml

# Kaniko (plugins/docker) does not execute heredoc RUN. Exec-form bash -c avoids shell-form $$ escaping
# ($$TOKEN in bash is PID+TOKEN, not the secret; use JSON array so $TOKEN is passed through to bash).
# Read GITHUB_TOKEN from BuildKit /run/secrets/ (local) or /kaniko/run/secrets/ (CI plugin staging).
RUN --mount=type=secret,id=GITHUB_TOKEN,required=false \
  ["/bin/bash", "-c", "set -e; TOKEN=; if [ -f /run/secrets/GITHUB_TOKEN ] && [ -s /run/secrets/GITHUB_TOKEN ]; then TOKEN=$(tr -d '\\n' < /run/secrets/GITHUB_TOKEN); elif [ -f /kaniko/run/secrets/GITHUB_TOKEN ] && [ -s /kaniko/run/secrets/GITHUB_TOKEN ]; then TOKEN=$(tr -d '\\n' < /kaniko/run/secrets/GITHUB_TOKEN); fi; if [ -n \"${TOKEN}\" ]; then git config --global url.\"https://${TOKEN}:@github.com/\".insteadOf \"https://github.com/\"; fi; cd /tmp/workspace && uv sync --python 3.12 --no-editable; rm -rf /root/.cache/uv; find /opt/bietlejuice/venvs -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true; find /opt/bietlejuice/venvs -name '*.pyc' -delete 2>/dev/null || true; if [ -n \"${TOKEN}\" ]; then git config --global --remove-section url.\"https://${TOKEN}:@github.com/\" || true; fi; rm -rf /tmp/workspace"]

###############################################################################
# Target: ci-jdk — ci-base + JRE for PySpark + dbr-16-4 venv
###############################################################################
FROM ci-base AS ci-jdk

# Kaniko (CI) does not always expand BuildKit TARGETARCH for ENV, which left
# JAVA_HOME as /usr/lib/jvm/java-17-openjdk- (broken). Resolve the JRE path
# after install and point JAVA_HOME at a stable symlink (works amd64 + arm64).
RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends \
  openjdk-17-jre-headless \
  && rm -rf /var/lib/apt/lists/* \
  && jhome="$(dirname "$(dirname "$(readlink -f /usr/bin/java)")")" \
  && ln -sfn "$jhome" /usr/lib/jvm/ci-openjdk-17

ENV JAVA_HOME=/usr/lib/jvm/ci-openjdk-17

# Pre-install the dbr-16-4 venv at build time (mirrors DBR 16.4 LTS pinned libs).
# Runtime venv is baked in the devcontainer target only (local dev / lint).
# UV_PROJECT_ENVIRONMENT is overridden inline; the inherited workspace value
# from ci-base is not used here.
COPY packages/bietlejuice-runtime/pyproject.toml /tmp/workspace/packages/bietlejuice-runtime/pyproject.toml
# [tool.hatch.build.hooks.custom] points here; Hatchling validates the path before wheel build.
COPY packages/bietlejuice-runtime/hatch_build.py /tmp/workspace/packages/bietlejuice-runtime/hatch_build.py
COPY packages/bietlejuice-runtime/uv.lock /tmp/workspace/packages/bietlejuice-runtime/uv.lock
COPY packages/bietlejuice-runtime/envs/dbr-16-4/pyproject.toml /tmp/workspace/packages/bietlejuice-runtime/envs/dbr-16-4/pyproject.toml
COPY packages/bietlejuice-runtime/envs/dbr-16-4/uv.lock /tmp/workspace/packages/bietlejuice-runtime/envs/dbr-16-4/uv.lock
COPY packages/bietlejuice-core/pyproject.toml /tmp/workspace/packages/bietlejuice-core/pyproject.toml

RUN --mount=type=secret,id=GITHUB_TOKEN,required=false \
  ["/bin/bash", "-c", "set -e; TOKEN=; if [ -f /run/secrets/GITHUB_TOKEN ] && [ -s /run/secrets/GITHUB_TOKEN ]; then TOKEN=$(tr -d '\\n' < /run/secrets/GITHUB_TOKEN); elif [ -f /kaniko/run/secrets/GITHUB_TOKEN ] && [ -s /kaniko/run/secrets/GITHUB_TOKEN ]; then TOKEN=$(tr -d '\\n' < /kaniko/run/secrets/GITHUB_TOKEN); fi; if [ -n \"${TOKEN}\" ]; then git config --global url.\"https://${TOKEN}:@github.com/\".insteadOf \"https://github.com/\"; fi; cd /tmp/workspace && UV_PROJECT_ENVIRONMENT=/opt/bietlejuice/venvs/dbr-16-4 uv sync --directory packages/bietlejuice-runtime/envs/dbr-16-4 --python 3.12 --no-editable; rm -rf /root/.cache/uv; find /opt/bietlejuice/venvs -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true; find /opt/bietlejuice/venvs -name '*.pyc' -delete 2>/dev/null || true; if [ -n \"${TOKEN}\" ]; then git config --global --remove-section url.\"https://${TOKEN}:@github.com/\" || true; fi; rm -rf /tmp/workspace"]

# Warm Ivy cache for Delta Lake JARs used by unit-tests-dags Spark+Delta integration
# tests (delta-spark==3.3.1 / DBR 16.4). Build agents reach Maven; Woodpecker test
# agents do not — Spark resolves from /root/.ivy2 offline at runtime.
RUN JAVA_HOME=/usr/lib/jvm/ci-openjdk-17 \
  /opt/bietlejuice/venvs/dbr-16-4/bin/python -c "\
from pyspark.sql import SparkSession; \
from delta import configure_spark_with_delta_pip; \
spark = configure_spark_with_delta_pip( \
  SparkSession.builder.master('local[1]').appName('prefetch-delta-jars') \
).getOrCreate(); \
spark.stop()"

###############################################################################
# Target: devcontainer — ci-jdk + dev tooling
###############################################################################
FROM ci-jdk AS devcontainer

# Pre-install the runtime venv for local dev (not needed in prod-ci-jdk-latest).
COPY packages/bietlejuice-runtime/pyproject.toml /tmp/workspace/packages/bietlejuice-runtime/pyproject.toml
COPY packages/bietlejuice-runtime/hatch_build.py /tmp/workspace/packages/bietlejuice-runtime/hatch_build.py
COPY packages/bietlejuice-runtime/uv.lock /tmp/workspace/packages/bietlejuice-runtime/uv.lock
COPY packages/bietlejuice-core/pyproject.toml /tmp/workspace/packages/bietlejuice-core/pyproject.toml

RUN --mount=type=secret,id=GITHUB_TOKEN,required=false \
  ["/bin/bash", "-c", "set -e; TOKEN=; if [ -f /run/secrets/GITHUB_TOKEN ] && [ -s /run/secrets/GITHUB_TOKEN ]; then TOKEN=$(tr -d '\\n' < /run/secrets/GITHUB_TOKEN); elif [ -f /kaniko/run/secrets/GITHUB_TOKEN ] && [ -s /kaniko/run/secrets/GITHUB_TOKEN ]; then TOKEN=$(tr -d '\\n' < /kaniko/run/secrets/GITHUB_TOKEN); fi; if [ -n \"${TOKEN}\" ]; then git config --global url.\"https://${TOKEN}:@github.com/\".insteadOf \"https://github.com/\"; fi; cd /tmp/workspace && UV_PROJECT_ENVIRONMENT=/opt/bietlejuice/venvs/runtime uv sync --directory packages/bietlejuice-runtime --python 3.12 --no-editable; rm -rf /root/.cache/uv; find /opt/bietlejuice/venvs -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true; find /opt/bietlejuice/venvs -name '*.pyc' -delete 2>/dev/null || true; if [ -n \"${TOKEN}\" ]; then git config --global --remove-section url.\"https://${TOKEN}:@github.com/\" || true; fi; rm -rf /tmp/workspace"]

ARG YQ_VERSION
ARG AWSCLI_VERSION
ARG DATABRICKS_CLI_VERSION
ARG ASTRO_CLI_VERSION
ARG STARSHIP_VERSION
ARG WEEP_VERSION
ARG WOODPECKER_CLI_VERSION
ARG TARGETARCH

RUN rm -f /etc/apt/apt.conf.d/docker-clean

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && apt-get install -y --no-install-recommends \
  curl \
  ssh \
  ca-certificates \
  sudo \
  zsh \
  jq \
  ripgrep \
  unzip \
  gnupg \
  locales \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
  && locale-gen \
  && update-locale LANG=en_US.UTF-8

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LANGUAGE=en_US:en

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked <<EOS
set -e
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  > /etc/apt/keyrings/githubcli-archive-keyring.gpg
chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list
apt-get update
apt-get install -y --no-install-recommends gh
EOS

COPY .devcontainer/install_devcontainer_tools.sh /usr/local/bin/install_devcontainer_tools.sh
RUN chmod +x /usr/local/bin/install_devcontainer_tools.sh \
  && /usr/local/bin/install_devcontainer_tools.sh \
    "${TARGETARCH}" \
    "${ASTRO_CLI_VERSION}" \
    "${YQ_VERSION}" \
    "${AWSCLI_VERSION}" \
    "${DATABRICKS_CLI_VERSION}" \
    "${STARSHIP_VERSION}" \
    "${WEEP_VERSION}" \
    "${WOODPECKER_CLI_VERSION}"

RUN groupadd --gid 1000 vscode \
  && useradd --uid 1000 --gid 1000 --create-home --shell /usr/bin/zsh vscode \
  && mkdir -p /etc/sudoers.d \
  && echo "vscode ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vscode \
  && chmod 0440 /etc/sudoers.d/vscode \
  && mkdir -p /home/vscode/.weep \
  && chown -R vscode:vscode /home/vscode/.weep

# Chown venvs so post-create can re-link editables.
RUN chown -R vscode:vscode /opt/bietlejuice

COPY .devcontainer/starship.toml /home/vscode/.config/starship.toml
COPY .devcontainer/zshrc /home/vscode/.zshrc

RUN mkdir -p /workspaces/bi-etl-ejuice \
  && chown -R vscode:vscode /workspaces /home/vscode/.config /home/vscode/.zshrc \
  && sudo -u vscode git config --global --add safe.directory /workspaces/bi-etl-ejuice \
  && sudo -u vscode git config --global core.untrackedCache true

USER vscode
WORKDIR /workspaces/bi-etl-ejuice
