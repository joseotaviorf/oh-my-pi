# syntax=docker/dockerfile:1
#
# Local Astro image for bi-etl-ejuice.
#
# Follows Astronomer's recommended customization pattern for `-base` Runtime
# images: install Python deps directly into the runtime's system Python via the
# bundled `install-python-dependencies` script (no parallel venv). See
# https://www.astronomer.io/docs/astro/cli/customize-dockerfile.
#
# Notes:
# - apache-airflow MUST NOT appear in requirements.txt; the install script
#   refuses such builds. Our `make setup-bietlejuice` exports
#   bietlejuice-airflow's runtime deps via `uv export --no-dev`, and
#   apache-airflow lives only in the dev group of packages/bietlejuice-airflow,
#   so it is excluded from the export by design.
# - quintoandar-logger is fetched from a private GitHub URL inside
#   requirements.txt; pip needs GITHUB_TOKEN at install time, passed via a
#   BuildKit secret mount.
# - bietlejuice-core and bietlejuice-airflow source trees are bind-mounted at
#   runtime via docker-compose.override.yml; PYTHONPATH below points at those
#   mount targets so DAGs can import bietlejuice without an editable install.
FROM astrocrpublic.azurecr.io/astronomer/astro-runtime:13.4.0-base

USER root

COPY packages.txt .
RUN /usr/local/bin/install-system-packages

COPY requirements.txt custom_requirements.txt ./
RUN --mount=type=secret,id=GITHUB_TOKEN,uid=50000,gid=0 <<'EOS'
set -e
TOKEN=""
if [ -f /run/secrets/GITHUB_TOKEN ] && [ -s /run/secrets/GITHUB_TOKEN ]; then
  TOKEN=$(tr -d '\n' < /run/secrets/GITHUB_TOKEN)
  git config --global url."https://${TOKEN}:@github.com/".insteadOf "https://github.com/"
fi
/usr/local/bin/install-python-dependencies
pip install --no-cache-dir --root-user-action=ignore --no-deps -r custom_requirements.txt
if [ -n "$TOKEN" ]; then
  git config --global --remove-section url."https://${TOKEN}:@github.com/" || true
fi
EOS

# plugins/ holds databricks_plugin (from clone-local-beethoven); its parent must be on
# PYTHONPATH so `import databricks_plugin` works during DAG import (not only via Airflow plugin hooks).
ENV PYTHONPATH="/usr/local/airflow:/usr/local/airflow/plugins:/usr/local/bietlejuice/core-src:/usr/local/bietlejuice/airflow-src" \
  ENVIRONMENT=forno \
  AIRFLOW__CORE__DAGBAG_IMPORT_TIMEOUT=90 \
  AIRFLOW__CORE__DAG_IGNORE_FILE_SYNTAX=glob \
  AIRFLOW__CORE__MAX_TEMPLATED_FIELD_LENGTH=16384 \
  AIRFLOW__SCHEDULER__CATCHUP_BY_DEFAULT=False \
  AIRFLOW__WEBSERVER__SHOW_TRIGGER_FORM_IF_NO_PARAMS=True

USER astro
COPY --chown=astro:0 . .
WORKDIR /usr/local/airflow
