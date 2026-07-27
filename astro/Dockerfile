# syntax=docker/dockerfile:1
ARG UV_VERSION=0.11.7

FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv-bin

# Airflow 2.x Runtime on quay.io (azurecr times out from Woodpecker agents).
# Stay on `-base` so ONBUILD does not `COPY . .` from the monorepo root context.
# We still run the same install helpers the non-base image uses in ONBUILD:
#   packages.txt  → /usr/local/bin/install-system-packages
#   requirements.txt → /usr/local/bin/install-python-dependencies
# See https://www.astronomer.io/docs/astro/cli/customize-dockerfile
# and https://www.astronomer.io/docs/runtime/runtime-image-architecture
FROM quay.io/astronomer/astro-runtime:13.8.0-base AS production

USER root
WORKDIR /usr/local/airflow

COPY --from=uv-bin /uv /uvx /usr/local/bin/

# Mirror Runtime ONBUILD: OS packages
COPY astro/packages.txt packages.txt
RUN /usr/local/bin/install-system-packages

# Dataset-cleaning guard (skip DDRQ DAGs missing SerializedDagModel) is upstream
# in Airflow 2.11.2+astro.3 / Runtime 13.7+ (AF #63546) — no local patch needed.
COPY astro/parse-alias-batching.patch /tmp/parse-alias-batching.patch
RUN cd /usr/local/lib/python3.12/site-packages \
    && patch -p1 --forward -i /tmp/parse-alias-batching.patch \
    && rm /tmp/parse-alias-batching.patch

# Mirror Runtime ONBUILD: requirements.txt extras (e.g. VaultBackend provider)
COPY astro/requirements.txt requirements.txt
RUN /usr/local/bin/install-python-dependencies

# Monorepo Python packages (bietlejuice-specific; not part of Astro ONBUILD).
# GITHUB_TOKEN via BuildKit secret (/run/secrets/) — same as local docker build --secret.
# --no-sources: package pyprojects use workspace/git sources that don't apply here.
COPY astro/runtime-constraints.txt /tmp/runtime-constraints.txt
COPY packages/bietlejuice-core /tmp/packages/bietlejuice-core
COPY packages/bietlejuice-airflow /tmp/packages/bietlejuice-airflow
COPY packages/bietlejuice-airflow-operators /tmp/packages/bietlejuice-airflow-operators
COPY packages/bietlejuice-airflow-plugins /tmp/packages/bietlejuice-airflow-plugins

RUN --mount=type=secret,id=GITHUB_TOKEN \
  ["/bin/bash", "-c", "set -euo pipefail; set +x; TOKEN=$(tr -d '\\n' < /run/secrets/GITHUB_TOKEN); if [ -z \"${TOKEN}\" ]; then echo 'GITHUB_TOKEN secret empty' >&2; exit 1; fi; git config --global url.\"https://${TOKEN}:@github.com/\".insteadOf \"https://github.com/\"; set -x; uv pip install --system --no-cache --no-sources --constraint /tmp/runtime-constraints.txt \"quintoandar-logger @ git+https://github.com/quintoandar/python-logger@0.8.1\" /tmp/packages/bietlejuice-core /tmp/packages/bietlejuice-airflow-plugins /tmp/packages/bietlejuice-airflow /tmp/packages/bietlejuice-airflow-operators; set +x; git config --global --remove-section url.\"https://${TOKEN}:@github.com/\" || true; rm -rf /tmp/packages /tmp/runtime-constraints.txt"]

ENV PYTHONPATH="/usr/local/bietlejuice/core-src:/usr/local/bietlejuice/airflow-src:/usr/local/bietlejuice/operators-src:/usr/local/bietlejuice/plugins-src:/usr/local/airflow" \
  ENVIRONMENT=forno \
  BIETLEJUICE_TRUST_MANIFESTS=1 \
  AIRFLOW__CORE__DAGBAG_IMPORT_TIMEOUT=90 \
  AIRFLOW__CORE__DAG_IGNORE_FILE_SYNTAX=glob \
  AIRFLOW__CORE__MAX_TEMPLATED_FIELD_LENGTH=16384 \
  AIRFLOW__SCHEDULER__CATCHUP_BY_DEFAULT=False \
  AIRFLOW__WEBSERVER__SHOW_TRIGGER_FORM_IF_NO_PARAMS=True

# Parse-time pre-warm: imported by Airflow as airflow_local_settings from $AIRFLOW_HOME/config
# (added to sys.path in settings.prepare_syspath_for_config_and_plugins).
COPY astro/config/ /usr/local/airflow/config/

USER astro
