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
#   docker-static    — helper stage: pinned Docker Engine static binaries.
#                      Used by later stages via COPY --from=docker-static.
#
#   ci-jdk           — ci-base + openjdk-17-jre-headless +
#                      dbr-16-4 venv at /opt/bietlejuice/venvs/dbr-16-4.
#                      Used by test CI steps (PySpark needs a JVM).
#
#   devcontainer     — ci-jdk + runtime venv at /opt/bietlejuice/venvs/runtime +
#                      dev tooling (vscode user, sudo, zsh, Starship prompt, gh,
#                      AWS CLI v2, Databricks CLI, yq, jq, ripgrep, astro-cli,
#                      weep, woodpecker-cli, QLI, docker CLI + buildx + compose (DooD)).
#                      Inherits workspace + dbr-16-4 from ci-jdk; adds runtime.
#
#   ci-astro         — ci-base + Astro CLI (pinned ASTRO_CLI_VERSION).
#                      Used by .woodpecker/development.yml Astro DAG deploy steps.
#                      Local builds may be amd64 or arm64; ECR publish remains amd64-only.
#
#   ci-astro-dind    — ci-astro + Docker Engine 29.6.2 static binaries (DinD).
#                      Debian-based alternative to stock docker:dind for Astro image deploy.
#
# Kaniko builds all stages that appear before --target; keep Astro/DinD after
# devcontainer so PR validate does not build DinD apt under QEMU.
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
#   make build-ci-container-astro      # → bi-etl-ejuice-ci:astro-latest
#   make build-ci-container-astro-dind # → bi-etl-ejuice-ci:astro-dind-latest
#   make build-ci-container-jdk        # → bi-etl-ejuice-ci:jdk-latest
#   make build-devcontainer        # → bi-etl-ejuice:devcontainer-latest
#
# ci-base / ci-jdk / devcontainer are multi-arch capable (amd64 + arm64).
# ci-astro / ci-astro-dind ECR publish remains amd64-only. Use PLATFORM=linux/amd64
# with Makefile targets for cross-arch local builds.

ARG UV_VERSION=0.12.0
ARG ASTRO_CLI_VERSION=1.43.1
ARG YQ_VERSION=4.53.3
ARG AWSCLI_VERSION=2.36.10
ARG DATABRICKS_CLI_VERSION=1.10.0
ARG STARSHIP_VERSION=1.26.0
ARG WEEP_VERSION=0.3.31
ARG WOODPECKER_CLI_VERSION=3.16.0
ARG DOCKER_VERSION=29.6.2
ARG DOCKER_BUILDX_VERSION=0.35.0
ARG DOCKER_COMPOSE_VERSION=5.3.1

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
COPY packages/bietlejuice-airflow-operators/pyproject.toml /tmp/workspace/packages/bietlejuice-airflow-operators/pyproject.toml
COPY packages/bietlejuice-airflow-plugins/pyproject.toml /tmp/workspace/packages/bietlejuice-airflow-plugins/pyproject.toml
COPY packages/bietlejuice-compiler/pyproject.toml /tmp/workspace/packages/bietlejuice-compiler/pyproject.toml
COPY packages/bietlejuice-runtime/pyproject.toml /tmp/workspace/packages/bietlejuice-runtime/pyproject.toml

# Kaniko (plugins/docker) does not execute heredoc RUN. Exec-form bash -c avoids shell-form $$ escaping
# ($$TOKEN in bash is PID+TOKEN, not the secret; use JSON array so $TOKEN is passed through to bash).
# Read GITHUB_TOKEN from BuildKit /run/secrets/ (local) or /kaniko/run/secrets/ (CI plugin staging).
RUN --mount=type=secret,id=GITHUB_TOKEN,required=false \
  ["/bin/bash", "-c", "set -e; TOKEN=; if [ -f /run/secrets/GITHUB_TOKEN ] && [ -s /run/secrets/GITHUB_TOKEN ]; then TOKEN=$(tr -d '\\n' < /run/secrets/GITHUB_TOKEN); elif [ -f /kaniko/run/secrets/GITHUB_TOKEN ] && [ -s /kaniko/run/secrets/GITHUB_TOKEN ]; then TOKEN=$(tr -d '\\n' < /kaniko/run/secrets/GITHUB_TOKEN); fi; if [ -n \"${TOKEN}\" ]; then git config --global url.\"https://${TOKEN}:@github.com/\".insteadOf \"https://github.com/\"; fi; cd /tmp/workspace && uv sync --python 3.12 --no-editable; rm -rf /root/.cache/uv; find /opt/bietlejuice/venvs -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true; find /opt/bietlejuice/venvs -name '*.pyc' -delete 2>/dev/null || true; if [ -n \"${TOKEN}\" ]; then git config --global --remove-section url.\"https://${TOKEN}:@github.com/\" || true; fi; rm -rf /tmp/workspace"]

###############################################################################
# Stage: docker-static — pinned Docker Engine static binaries (no apt build tooling)
###############################################################################
FROM debian:bookworm-slim AS docker-static

ARG DOCKER_VERSION
ARG DOCKER_BUILDX_VERSION
ARG DOCKER_COMPOSE_VERSION
ARG DIND_COMMIT=8d9e3502aba39127e4d12196dae16d306f76993d
ARG TARGETARCH

RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  mkdir -p /out/usr/local/bin /out/usr/local/libexec/docker/cli-plugins; \
  case "${TARGETARCH}" in \
    amd64) DOCKER_ARCH=x86_64 ;; \
    arm64) DOCKER_ARCH=aarch64 ;; \
    *) echo >&2 "error: unsupported TARGETARCH (${TARGETARCH})"; exit 1 ;; \
  esac; \
  curl -fsSL "https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz" -o /tmp/docker.tgz; \
  tar --extract --file /tmp/docker.tgz --strip-components 1 --directory /out/usr/local/bin --no-same-owner; \
  rm /tmp/docker.tgz; \
  curl -fsSL "https://github.com/docker/buildx/releases/download/v${DOCKER_BUILDX_VERSION}/buildx-v${DOCKER_BUILDX_VERSION}.linux-${TARGETARCH}" \
    -o /out/usr/local/libexec/docker/cli-plugins/docker-buildx; \
  chmod +x /out/usr/local/libexec/docker/cli-plugins/docker-buildx; \
  curl -fsSL "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${DOCKER_ARCH}" \
    -o /out/usr/local/libexec/docker/cli-plugins/docker-compose; \
  chmod +x /out/usr/local/libexec/docker/cli-plugins/docker-compose; \
  curl -fsSL "https://raw.githubusercontent.com/moby/moby/${DIND_COMMIT}/hack/dind" \
    -o /out/usr/local/bin/dind; \
  chmod 0755 /out/usr/local/bin/dind

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
  socat \
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

COPY .devcontainer/starship.toml /home/vscode/.config/starship.toml
COPY .devcontainer/zshrc /home/vscode/.zshrc

RUN mkdir -p /workspaces/bi-etl-ejuice \
  && chown -R vscode:vscode /workspaces /home/vscode/.config /home/vscode/.zshrc \
  && sudo -u vscode git config --global --add safe.directory /workspaces/bi-etl-ejuice \
  && sudo -u vscode git config --global core.untrackedCache true

# Docker-outside-of-Docker: CLI only (host daemon via socket). Not DinD.
COPY --from=docker-static /out/usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-static /out/usr/local/libexec/docker/cli-plugins/docker-buildx \
  /usr/local/libexec/docker/cli-plugins/docker-buildx
COPY --from=docker-static /out/usr/local/libexec/docker/cli-plugins/docker-compose \
  /usr/local/libexec/docker/cli-plugins/docker-compose
RUN ln -sf /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose \
  && docker --version \
  && docker buildx version \
  && docker compose version

COPY .devcontainer/docker-init.sh /usr/local/share/docker-init.sh
RUN chmod +x /usr/local/share/docker-init.sh \
  && groupadd --system docker \
  && usermod -aG docker vscode \
  && mkdir -p /var/run \
  && touch /var/run/docker-host.sock \
  && ln -sf /var/run/docker-host.sock /var/run/docker.sock \
  && chown -h vscode:root /var/run/docker.sock

USER vscode
WORKDIR /workspaces/bi-etl-ejuice
ENTRYPOINT ["/usr/local/share/docker-init.sh"]
CMD ["sleep", "infinity"]

###############################################################################
# Target: ci-astro — ci-base + Astro CLI (Woodpecker development.yml DAG deploy)
# Local builds may be amd64 or arm64; ECR publish remains amd64-only.
###############################################################################
FROM ci-base AS ci-astro

ARG ASTRO_CLI_VERSION
ARG TARGETARCH

# Same tarball install as .devcontainer/install_devcontainer_tools.sh (astro only).
RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends curl ca-certificates \
  && case "${TARGETARCH}" in \
       amd64|x86_64) ASTRO_ARCH=amd64 ;; \
       arm64|aarch64) ASTRO_ARCH=arm64 ;; \
       *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
     esac \
  && curl -fsSL "https://github.com/astronomer/astro-cli/releases/download/v${ASTRO_CLI_VERSION}/astro_${ASTRO_CLI_VERSION}_linux_${ASTRO_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin astro \
  && rm -rf /var/lib/apt/lists/* \
  && astro version

###############################################################################
# Target: ci-astro-dind — ci-astro + Docker-in-Docker (Debian, static Engine)
###############################################################################
FROM ci-astro AS ci-astro-dind

USER root

RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends \
    iptables \
    e2fsprogs \
    xfsprogs \
    btrfs-progs \
    pigz \
    xz-utils \
    openssl \
    uidmap \
    iproute2 \
    kmod \
  && rm -rf /var/lib/apt/lists/*

# iptables-legacy symlink farm (Debian paths under /usr/sbin)
RUN set -eux; \
  mkdir -p /usr/local/sbin/.iptables-legacy; \
  for f in \
    iptables iptables-save iptables-restore \
    ip6tables ip6tables-save ip6tables-restore \
  ; do \
    b="$(command -v "${f/tables/tables-legacy}")"; \
    "$b" --version; \
    ln -svT "$b" "/usr/local/sbin/.iptables-legacy/$f"; \
  done; \
  export PATH="/usr/local/sbin/.iptables-legacy:$PATH"; \
  iptables --version | grep legacy

# subuid/subgid for --userns-remap=default
RUN set -eux; \
  groupadd -r dockremap; \
  useradd -r -g dockremap dockremap; \
  echo 'dockremap:165536:65536' >> /etc/subuid; \
  echo 'dockremap:165536:65536' >> /etc/subgid

COPY --from=docker-static /out/usr/local/ /usr/local/

COPY .container/dind/modprobe.sh /usr/local/bin/modprobe
COPY .container/dind/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY .container/dind/dockerd-entrypoint.sh /usr/local/bin/dockerd-entrypoint.sh

RUN chmod +x /usr/local/bin/modprobe /usr/local/bin/docker-entrypoint.sh /usr/local/bin/dockerd-entrypoint.sh \
  && docker --version \
  && dockerd --version \
  && containerd --version \
  && runc --version \
  && docker buildx version \
  && astro version

ENV DOCKER_TLS_CERTDIR=/certs
RUN mkdir -p /certs /certs/client && chmod 1777 /certs /certs/client

VOLUME /var/lib/docker
EXPOSE 2375 2376

ENTRYPOINT ["dockerd-entrypoint.sh"]
CMD []
