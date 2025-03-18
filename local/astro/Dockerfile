# syntax=docker/dockerfile:1
FROM quay.io/astronomer/astro-runtime:12.6.0 AS stage1

LABEL maintainer="Astronomer <humans@astronomer.io>"
ARG BUILD_NUMBER=-1
LABEL io.astronomer.docker=true
LABEL io.astronomer.docker.build.number=$BUILD_NUMBER
LABEL io.astronomer.docker.airflow.onbuild=true
# Install Python and OS-Level Packages

USER root
COPY packages.txt .
RUN apt-get update && cat packages.txt | xargs apt-get install -y

FROM stage1 AS stage2

RUN --mount=type=bind,target=. \
  --mount=type=secret,id=GITHUB_TOKEN \
  git config --global url.https://$(cat /run/secrets/GITHUB_TOKEN):@github.com/.insteadOf https://github.com/

# Installing bi-etl-ejuice dependencies
RUN pip install -qq -r ./custom_requirements.txt --extra-index-url https://quintoandar.github.io/python-package-server/ --no-deps

ENV ENVIRONMENT=forno
ENV AIRFLOW__CORE__DAGBAG_IMPORT_TIMEOUT=90
ENV AIRFLOW__CORE__DAG_IGNORE_FILE_SYNTAX=glob
ENV AIRFLOW__CORE__MAX_TEMPLATED_FIELD_LENGTH=16384
ENV AIRFLOW__SCHEDULER__CATCHUP_BY_DEFAULT=False

RUN chmod -R 755 .
COPY . .
RUN chmod -R 755 .

USER astro
