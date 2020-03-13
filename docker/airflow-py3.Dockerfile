FROM python:3.6.8

LABEL maintainer='Data Engineer Team'

WORKDIR /bi-etl-ejuice

ARG AIRFLOW_VERSION=1.10.3
ENV PYTHONIOENCODING=utf-8 \
    AIRFLOW_HOME=/bi-etl-ejuice/airflow_python3 \
    PYTHONPATH="${PYTHONPATH}:/${AIRFLOW_HOME}/config" \
    SLUGIFY_USES_TEXT_UNIDECODE=yes \
    AIRFLOW_GPL_UNIDECODE=yes

RUN apt-get update && \
    apt-get install -y \
    python-pip \
    python-dev \
    python-setuptools \
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

COPY requirements3_local.txt .

# This step will be improve with a new step that get your github authentication from your machine.
# Until there, let's use this primitive way :D
RUN python3 -m pip install --upgrade pip && \
    git config --global url.https://<GITHUB_TOKEN>:@github.com/.insteadOf https://github.com/ && \
    pip install -r requirements3_local.txt --extra-index-url https://quintoandar.github.io/python-package-server/ && \
    git clone https://github.com/quintoandar/airflow-plugins.git && \
    locale-gen --purge pt_BR.UTF-8

COPY . .

RUN chmod +x start.sh && \
    /bin/bash -c 'cp -R /bi-etl-ejuice/airflow-plugins/quintoandar_airflow_plugins/* /bi-etl-ejuice/airflow_python3/plugins && rm -R /bi-etl-ejuice/airflow-plugins'

ENTRYPOINT /bi-etl-ejuice/start.sh