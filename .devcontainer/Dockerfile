# syntax=docker/dockerfile:1.10
#
# Multi-stage build for the bi-etl-ejuice devcontainer.
#
# Stages:
#   - `builder`  — installs compile toolchains (build-essential, python3-dev,
#                  liblz4-dev, openjdk-17-jdk), pre-builds the three uv venvs,
#                  and stages the Astro CLI tarball. Heavy, ephemeral — never
#                  ships to the runtime image.
#   - `runtime`  — final image. Carries the JRE-headless, the three venvs,
#                  the uv binary, the Astro CLI, plus a small dev toolbelt
#                  (gh, jq, yq, ripgrep, AWS CLI v2, Databricks CLI).
#                  build-essential, the JDK, and the uv wheel cache do NOT
#                  land here.
#
# The two `bietlejuice-runtime` venvs are pre-staged at
# /opt/bietlejuice-runtime-venvs/{root,dbr-16-4} so they live OUTSIDE the
# future /workspaces/bi-etl-ejuice/ bind-mount. post-create.sh symlinks them
# back into the workspace tree at container-creation time, after the
# bind-mount is in place.
#
# When bumping pinned versions, keep them aligned with the host:
#   - UV_VERSION should match `uv --version` on the host (resolver drift
#     between host- and container-side uv would cause `uv sync` failures
#     after a host-side `uv.lock` regeneration).
#   - ASTRO_CLI_VERSION should match the Astro Runtime in `local/astro/`
#     (schema drift breaks `astro dev`).
#   - BASE_IMAGE_DIGEST pins `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`
#     to the manifest-list digest at build time. Renovate / Dependabot can
#     auto-bump this.

ARG BASE_IMAGE_DIGEST=sha256:d94c97dd9cacf183d0a6fd12a8e87b526e9e928307674ae9c94139139c0c6eae
ARG UV_VERSION=0.11.7
ARG ASTRO_CLI_VERSION=1.41.0
ARG YQ_VERSION=4.45.1
ARG AWSCLI_VERSION=2.34.34
ARG DATABRICKS_CLI_VERSION=0.298.0

###############################################################################
# Stage: uv-bin — alias the pinned uv image so `COPY --from=uv-bin ...` below
# is a literal stage reference. `COPY --from=<image>:${VAR}` cannot expand
# ARGs in the image reference, so we materialize the version into a stage.
###############################################################################
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv-bin

###############################################################################
# Stage: builder — compile + dependency install. Discarded after stage exits.
###############################################################################
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04@${BASE_IMAGE_DIGEST} AS builder

ARG UV_VERSION
ARG ASTRO_CLI_VERSION
ARG TARGETARCH

# Drop /etc/apt/apt.conf.d/docker-clean so BuildKit cache mounts on /var/cache/apt
# and /var/lib/apt actually retain content between builds (the upstream Ubuntu
# image installs that file, which deletes the apt cache after every install).
RUN rm -f /etc/apt/apt.conf.d/docker-clean

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      python3-dev \
      liblz4-dev \
      openjdk-17-jdk

# uv binary (includes uvx). Pinned via the uv-bin stage above.
COPY --from=uv-bin /uv /uvx /usr/local/bin/

# Astro CLI: download a pinned tarball into a staging tree that the runtime
# stage will `COPY --from=builder ...`. Replaces the unpinned
# `curl install.astronomer.io | bash` pattern.
RUN mkdir -p /opt/astro-staging/usr/local/bin && \
    curl -fsSL "https://github.com/astronomer/astro-cli/releases/download/v${ASTRO_CLI_VERSION}/astro_${ASTRO_CLI_VERSION}_linux_${TARGETARCH}.tar.gz" \
      | tar -xz -C /opt/astro-staging/usr/local/bin astro

# Pre-create dirs owned by vscode so the venvs / cache get the right uid:gid
# from the start — no post-install chown needed.
RUN mkdir -p /opt/uv-cache /home/vscode/.venv \
      /opt/bietlejuice-runtime-venvs/root \
      /opt/bietlejuice-runtime-venvs/dbr-16-4 \
  && chown -R vscode:vscode /opt/uv-cache /home/vscode/.venv /opt/bietlejuice-runtime-venvs

ENV UV_CACHE_DIR=/opt/uv-cache \
    UV_PROJECT_ENVIRONMENT=/home/vscode/.venv

# Layer ordering: copy lock + manifest before package sources so a pure-source
# change can still hit the deeper apt/uv-binary/Astro layers in cache. The
# workspace `uv sync` itself reads source trees for editable installs, so a
# source-only change re-runs sync — but the third-party wheel install is
# served from /opt/uv-cache via the cache mount below.
COPY --chown=vscode:vscode pyproject.toml /tmp/workspace/pyproject.toml
COPY --chown=vscode:vscode uv.lock /tmp/workspace/uv.lock
COPY --chown=vscode:vscode packages/ /tmp/workspace/packages/

USER vscode
# Private Git deps (e.g. quintoandar-logger): pass the token as a BuildKit
# secret — never as a build-arg — so it doesn't persist in image config.
RUN --mount=type=cache,target=/opt/uv-cache,uid=1000,gid=1000 \
    --mount=type=secret,id=GITHUB_TOKEN,uid=1000,gid=1000,required=false <<'EOS'
set -e
TOKEN=""
if [ -f /run/secrets/GITHUB_TOKEN ] && [ -s /run/secrets/GITHUB_TOKEN ]; then
  TOKEN=$(tr -d '\n' < /run/secrets/GITHUB_TOKEN)
  git config --global url."https://${TOKEN}:@github.com/".insteadOf "https://github.com/"
fi
cd /tmp/workspace
uv sync --python 3.12
# bietlejuice-runtime is a standalone uv project (not a workspace member).
# Build both its venvs and *move them outside the workspace* so they survive
# into the runtime image — the workspace path will be shadowed by the
# /workspaces/ bind-mount at container start.
( unset UV_PROJECT_ENVIRONMENT
  uv sync --directory /tmp/workspace/packages/bietlejuice-runtime --python 3.12
  mv /tmp/workspace/packages/bietlejuice-runtime/.venv \
     /opt/bietlejuice-runtime-venvs/root/.venv
  uv sync --directory /tmp/workspace/packages/bietlejuice-runtime/envs/dbr-16-4 --python 3.12
  mv /tmp/workspace/packages/bietlejuice-runtime/envs/dbr-16-4/.venv \
     /opt/bietlejuice-runtime-venvs/dbr-16-4/.venv
)
if [ -n "$TOKEN" ]; then
  git config --global --remove-section url."https://${TOKEN}:@github.com/" || true
fi
rm -rf /tmp/workspace
EOS

###############################################################################
# Stage: runtime — the final image. Only carries what's needed at runtime.
###############################################################################
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04@${BASE_IMAGE_DIGEST} AS runtime

ARG YQ_VERSION
ARG AWSCLI_VERSION
ARG DATABRICKS_CLI_VERSION
ARG TARGETARCH

RUN rm -f /etc/apt/apt.conf.d/docker-clean

# JRE-headless instead of the full JDK saves ~340 MB. PySpark only needs the
# JVM to start — never javac. liblz4-1 is the runtime shared lib for the
# Spark/Hadoop LZ4 codec (the `-dev` headers stay in the builder).
#
# python3 is REQUIRED even though we ship pre-built venvs: uv venvs symlink
# bin/python at the absolute path of the system Python they were built
# against (here /usr/bin/python3.12). Without python3 in the runtime, uv
# would treat the venv as linked to a non-existent interpreter and re-sync
# every package from scratch on first `uv sync`. The metapackage pulls
# python3.12 and libpython3.12 (numpy/pandas/etc. link against libpython).
#
# jq + ripgrep are general-purpose dev shell tools.
# unzip + gnupg are install-time prerequisites for AWS CLI v2 (zip tarball)
# and the GitHub CLI apt repo (gpg-signed package list).
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      python3 \
      openjdk-17-jre-headless \
      liblz4-1 \
      git \
      make \
      curl \
      ca-certificates \
      sudo \
      jq \
      ripgrep \
      unzip \
      gnupg

# GitHub CLI: official apt repo + signed-by keyring per
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md. `gh` is referenced
# by .devcontainer/post-create.sh as a fallback when GITHUB_TOKEN is unset; without
# it the fallback prints a confusing "command not found".
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

# Pinned third-party CLIs not in default apt:
#   - yq (Mike Farah's, Go binary): YAML query/edit; this repo is YAML-heavy
#     (DAG declarations, Woodpecker pipelines, governance metadata).
#   - AWS CLI v2: ad-hoc S3 inspection against the artifacts buckets.
#   - Databricks CLI: cluster/job inspection; pairs with the databricks-sdk
#     dep in packages/bietlejuice-runtime.
# Versions are bumpable via the ARGs at the top of this Dockerfile (Renovate
# / Dependabot can track them).
RUN <<EOS
set -e

# Map BuildKit TARGETARCH (amd64/arm64) to the AWS CLI's arch name.
case "${TARGETARCH}" in
  amd64) AWS_ARCH=x86_64 ;;
  arm64) AWS_ARCH=aarch64 ;;
  *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;;
esac

# yq
curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${TARGETARCH}" \
  -o /usr/local/bin/yq
chmod +x /usr/local/bin/yq

# AWS CLI v2
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}-${AWSCLI_VERSION}.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli
rm -rf /tmp/awscliv2.zip /tmp/aws

# Databricks CLI
curl -fsSL "https://github.com/databricks/cli/releases/download/v${DATABRICKS_CLI_VERSION}/databricks_cli_${DATABRICKS_CLI_VERSION}_linux_${TARGETARCH}.zip" -o /tmp/dbcli.zip
unzip -q /tmp/dbcli.zip -d /tmp/dbcli
mv /tmp/dbcli/databricks /usr/local/bin/databricks
rm -rf /tmp/dbcli /tmp/dbcli.zip
EOS

# JAVA_HOME via symlink — works on both amd64 and arm64.
RUN ln -sfn "$(dirname "$(dirname "$(readlink -f "$(which java)")")")" /usr/lib/jvm/default-java
# UV_CACHE_DIR is intentionally NOT set in the runtime image: the build-time
# cache mount lives at /opt/uv-cache but isn't copied forward (see comment
# below), and creating an empty owned-by-vscode /opt/uv-cache here would just
# add a layer for no benefit. Letting uv default to ~/.cache/uv keeps any
# in-container `uv sync` writes inside vscode's home — always writable, and
# consistent with how uv behaves outside the devcontainer.
ENV JAVA_HOME=/usr/lib/jvm/default-java \
    UV_PROJECT_ENVIRONMENT=/home/vscode/.venv

# COPY order: least-frequently-changing first, so deeper layers stay cached
# longer across rebuilds.
#   1. uv binary           — moves only when UV_VERSION bumps
#   2. Astro CLI           — moves only when ASTRO_CLI_VERSION bumps
#   3. bietlejuice-runtime — moves when packages/bietlejuice-runtime/uv.lock or
#                            envs/dbr-16-4/uv.lock change
#   4. workspace venv      — moves when root uv.lock or any workspace
#                            package's pyproject.toml change (most frequent)
COPY --from=builder /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/
COPY --from=builder /opt/astro-staging/ /
COPY --from=builder --chown=vscode:vscode /opt/bietlejuice-runtime-venvs /opt/bietlejuice-runtime-venvs
COPY --from=builder --chown=vscode:vscode /home/vscode/.venv /home/vscode/.venv

# /opt/uv-cache is intentionally NOT copied from the builder. All wheels are
# already exploded into the three venvs above; uv's hash-based identity check
# recognizes them as installed without the cache, and post-create.sh's re-link
# of editable workspace packages doesn't need cache lookups. Saves ~600-800 MB.
# Off-the-happy-path cost: a dev who edits uv.lock locally will re-download
# new wheels from PyPI / private GitHub on the next in-container `uv sync`.

RUN mkdir -p /workspaces/bi-etl-ejuice \
  && chown -R vscode:vscode /workspaces

USER vscode
WORKDIR /workspaces/bi-etl-ejuice
