# syntax=docker/dockerfile:1
FROM quay.io/astronomer/astro-runtime:12.6.0-base AS builder

# Switch to root for OS-level installs
USER root
WORKDIR /root

COPY packages.txt .
RUN apt-get update && \
  cat packages.txt | xargs apt-get install -y --no-install-recommends --no-upgrade

USER astro
WORKDIR /home/astro

ENV PYTHONDONTWRITEBYTECODE=1 \
  PIP_DISABLE_PIP_VERSION_CHECK=1 \
  DEBIAN_FRONTEND=noninteractive

COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

COPY custom_requirements.txt .
RUN --mount=type=secret,id=GITHUB_TOKEN,uid=50000,gid=0 \
  export TOKEN=$(cat /run/secrets/GITHUB_TOKEN | tr -d '\n') && \
  git config --global url.https://${TOKEN}:@github.com/.insteadOf https://github.com/ && \
  pip install --user --no-cache-dir -r custom_requirements.txt --extra-index-url https://quintoandar.github.io/python-package-server/

FROM quay.io/astronomer/astro-runtime:12.6.0-base AS runtime

COPY --from=builder /home/astro/.local /home/astro/.local

ENV PATH="/home/astro/.local/bin:${PATH}"

ENV ENVIRONMENT=forno \
  AIRFLOW__CORE__DAGBAG_IMPORT_TIMEOUT=90 \
  AIRFLOW__CORE__DAG_IGNORE_FILE_SYNTAX=glob \
  AIRFLOW__CORE__MAX_TEMPLATED_FIELD_LENGTH=16384 \
  AIRFLOW__SCHEDULER__CATCHUP_BY_DEFAULT=False \
  AIRFLOW__WEBSERVER__SHOW_TRIGGER_FORM_IF_NO_PARAMS=True

COPY --chown=astro:0 . .

WORKDIR /usr/local/airflow
