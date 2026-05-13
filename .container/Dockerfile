# syntax=docker/dockerfile:1.10
#
# All container images for bi-etl-ejuice in a single multi-stage Dockerfile.
#
# Targets (build with `docker build --target <name>`):
#
#   ci-base          — python:3.12-slim-bookworm + git, make, rsync, uv +
#                      workspace venv at /opt/bietlejuice/venvs/workspace
#                      (core + airflow + compiler).
#                      Used by lint, validation, and release CI steps.
#
#   ci-jdk           — ci-base + openjdk-17-jre-headless +
#                      runtime venvs at /opt/bietlejuice/venvs/{runtime,dbr-16-4}.
#                      Used by test CI steps (PySpark needs a JVM).
#
#   devcontainer     — ci-jdk + dev tooling (vscode user, sudo, zsh,
#                      Starship prompt, gh, AWS CLI v2, Databricks CLI,
#                      yq, jq, ripgrep, astro-cli).
#                      Inherits all three venvs from ci-jdk.
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
ARG ASTRO_CLI_VERSION=1.41.0
ARG YQ_VERSION=4.45.1
ARG AWSCLI_VERSION=2.34.34
ARG DATABRICKS_CLI_VERSION=0.298.0
ARG STARSHIP_VERSION=1.25.0

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

RUN --mount=type=secret,id=GITHUB_TOKEN,required=false <<'EOS'
set -e
TOKEN=""
if [ -f /run/secrets/GITHUB_TOKEN ] && [ -s /run/secrets/GITHUB_TOKEN ]; then
  TOKEN=$(tr -d '\n' < /run/secrets/GITHUB_TOKEN)
  git config --global url."https://${TOKEN}:@github.com/".insteadOf "https://github.com/"
fi
cd /tmp/workspace && uv sync --python 3.12 --no-editable
rm -rf /tmp/workspace
if [ -n "$TOKEN" ]; then
  git config --global --remove-section url."https://${TOKEN}:@github.com/" || true
fi
EOS

###############################################################################
# Target: ci-jdk — ci-base + JRE for PySpark + runtime venvs
###############################################################################
FROM ci-base AS ci-jdk

ARG TARGETARCH

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
        openjdk-17-jre-headless \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-${TARGETARCH}

# Pre-install the runtime venvs at build time.
# bietlejuice-runtime (standalone project, separate lockfile) and
# bietlejuice-runtime/envs/dbr-16-4 (mirrors DBR 16.4 LTS pinned libs).
# UV_PROJECT_ENVIRONMENT is overridden inline per venv; the inherited
# /opt/bietlejuice/venvs/workspace value from ci-base is not used here.
COPY packages/bietlejuice-runtime/pyproject.toml /tmp/workspace/packages/bietlejuice-runtime/pyproject.toml
# [tool.hatch.build.hooks.custom] points here; Hatchling validates the path before wheel build.
COPY packages/bietlejuice-runtime/hatch_build.py /tmp/workspace/packages/bietlejuice-runtime/hatch_build.py
COPY packages/bietlejuice-runtime/uv.lock /tmp/workspace/packages/bietlejuice-runtime/uv.lock
COPY packages/bietlejuice-runtime/envs/dbr-16-4/pyproject.toml /tmp/workspace/packages/bietlejuice-runtime/envs/dbr-16-4/pyproject.toml
COPY packages/bietlejuice-runtime/envs/dbr-16-4/uv.lock /tmp/workspace/packages/bietlejuice-runtime/envs/dbr-16-4/uv.lock
COPY packages/bietlejuice-core/pyproject.toml /tmp/workspace/packages/bietlejuice-core/pyproject.toml

RUN --mount=type=secret,id=GITHUB_TOKEN,required=false <<'EOS'
set -e
TOKEN=""
if [ -f /run/secrets/GITHUB_TOKEN ] && [ -s /run/secrets/GITHUB_TOKEN ]; then
  TOKEN=$(tr -d '\n' < /run/secrets/GITHUB_TOKEN)
  git config --global url."https://${TOKEN}:@github.com/".insteadOf "https://github.com/"
fi
cd /tmp/workspace
UV_PROJECT_ENVIRONMENT=/opt/bietlejuice/venvs/runtime \
  uv sync --directory packages/bietlejuice-runtime --python 3.12 --no-editable
UV_PROJECT_ENVIRONMENT=/opt/bietlejuice/venvs/dbr-16-4 \
  uv sync --directory packages/bietlejuice-runtime/envs/dbr-16-4 --python 3.12 --no-editable
rm -rf /tmp/workspace
if [ -n "$TOKEN" ]; then
  git config --global --remove-section url."https://${TOKEN}:@github.com/" || true
fi
EOS

###############################################################################
# Target: devcontainer — ci-jdk + dev tooling
###############################################################################
FROM ci-jdk AS devcontainer

ARG YQ_VERSION
ARG AWSCLI_VERSION
ARG DATABRICKS_CLI_VERSION
ARG ASTRO_CLI_VERSION
ARG STARSHIP_VERSION
ARG TARGETARCH

RUN groupadd --gid 1000 vscode \
 && useradd --uid 1000 --gid 1000 --create-home --shell /usr/bin/zsh vscode \
 && mkdir -p /etc/sudoers.d \
 && echo "vscode ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vscode \
 && chmod 0440 /etc/sudoers.d/vscode

RUN rm -f /etc/apt/apt.conf.d/docker-clean

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      curl \
      ca-certificates \
      sudo \
      zsh \
      jq \
      ripgrep \
      unzip \
      gnupg

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

RUN <<EOS
set -e
case "${TARGETARCH}" in
  amd64) AWS_ARCH=x86_64 ;;
  arm64) AWS_ARCH=aarch64 ;;
  *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;;
esac

curl -fsSL "https://github.com/astronomer/astro-cli/releases/download/v${ASTRO_CLI_VERSION}/astro_${ASTRO_CLI_VERSION}_linux_${TARGETARCH}.tar.gz" \
  | tar -xz -C /usr/local/bin astro

curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${TARGETARCH}" \
  -o /usr/local/bin/yq
chmod +x /usr/local/bin/yq

curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}-${AWSCLI_VERSION}.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli
rm -rf /tmp/awscliv2.zip /tmp/aws

curl -fsSL "https://github.com/databricks/cli/releases/download/v${DATABRICKS_CLI_VERSION}/databricks_cli_${DATABRICKS_CLI_VERSION}_linux_${TARGETARCH}.zip" -o /tmp/dbcli.zip
unzip -q /tmp/dbcli.zip -d /tmp/dbcli
mv /tmp/dbcli/databricks /usr/local/bin/databricks
rm -rf /tmp/dbcli /tmp/dbcli.zip

curl -fsSL "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-${AWS_ARCH}-unknown-linux-musl.tar.gz" \
  | tar -xz -C /usr/local/bin starship
EOS

# All three venvs are inherited from ci-jdk at /opt/bietlejuice/venvs/.
# Chown to vscode so post-create.sh can re-link editable packages.
RUN chown -R vscode:vscode /opt/bietlejuice

COPY .container/starship.toml /home/vscode/.config/starship.toml
COPY .container/zshrc /home/vscode/.zshrc

RUN mkdir -p /workspaces/bi-etl-ejuice \
  && chown -R vscode:vscode /workspaces /home/vscode/.config /home/vscode/.zshrc

USER vscode
WORKDIR /workspaces/bi-etl-ejuice
