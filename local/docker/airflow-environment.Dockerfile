FROM python:3.8.12-slim

LABEL maintainer='Data Engineer Team'

WORKDIR /bi-etl-ejuice/local

ENV PYTHONIOENCODING=utf-8 \
    AIRFLOW_HOME=/bi-etl-ejuice/local/airflow \
    PYTHONPATH=":/bi-etl-ejuice/local" \
    SLUGIFY_USES_TEXT_UNIDECODE=yes \
    AIRFLOW_GPL_UNIDECODE=yes

RUN apt-get update -yqq && \
    apt-get install -yqq \
    python-dev \
    python-setuptools \
    default-libmysqlclient-dev \
    libpq-dev \
    libghc-persistent-postgresql-dev \
    build-essential \
    autoconf \
    libtool \
    libssl-dev \
    libffi-dev \
    vim \
    git \
    jq \
    locales

COPY local/requirements/requirements_local_composer.txt local/requirements/requirements_local_custom_libs.txt requirements.txt ./

ARG GITHUB_TOKEN

# This step will be improve with a new step that get your github authentication from your machine.
# Until there, let's use this primitive way :D
RUN python3 -m pip install -qq --upgrade pip && \
    git config --global url.https://${GITHUB_TOKEN}:@github.com/.insteadOf https://github.com/ && \
    pip install -qq -r requirements_local_composer.txt && \
    pip install -qq -r requirements_local_custom_libs.txt --extra-index-url https://quintoandar.github.io/python-package-server/ --no-deps && \
    pip install -qq -r requirements.txt && \
    git clone https://github.com/quintoandar/airflow-plugins.git && \
    locale-gen --purge pt_BR.UTF-8

COPY ./local/airflow ./airflow
COPY ./local/docker/entrypoint.sh ./entrypoint.sh
COPY ./bietlejuice ./bietlejuice

RUN mkdir /bi-etl-ejuice/local/airflow/plugins/ \
    && cp -R ./airflow-plugins/quintoandar_airflow_plugins/* ./airflow/plugins \
    && rm -R ./airflow-plugins
