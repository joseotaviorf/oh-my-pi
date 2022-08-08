FROM ubuntu:20.04

LABEL maintainer='Data Engineer Team'

WORKDIR /bi-etl-ejuice/local

ENV PYTHONIOENCODING=utf-8 \
    AIRFLOW_HOME=/bi-etl-ejuice/local/airflow \
    PYTHONPATH=":/bi-etl-ejuice/local" \
    SLUGIFY_USES_TEXT_UNIDECODE=yes \
    AIRFLOW_GPL_UNIDECODE=yes \
    DEBIAN_FRONTEND=noninteractive \
    JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64/jre/" \
    PYSPARK_DRIVER_PYTHON=python3 \
    PYSPARK_PYTHON=python3

RUN apt update -yqq && \
    apt install --no-install-recommends -yqq \
    software-properties-common \
    default-jdk && \
    add-apt-repository ppa:deadsnakes/ppa -y && \
    add-apt-repository ppa:openjdk-r/ppa -y && \
    apt update -yqq && \
    apt install --no-install-recommends -yqq \
    python3 \
    python3-dev \
    python3-pip \
    python3-setuptools \
    cython \
    openjdk-8-jdk \
    default-libmysqlclient-dev \
    libpq-dev \
    libghc-persistent-postgresql-dev \
    build-essential \
    autoconf \
    libtool \
    libssl-dev \
    libffi-dev \
    git \
    jq \
    locales && \
    rm -rf /var/lib/apt/lists/*

COPY local/requirements/requirements_local_composer.txt requirements_test.txt requirements.txt ./

ARG GITHUB_TOKEN

RUN python3 -m pip install -q --upgrade pip && \
    git config --global url.https://${GITHUB_TOKEN}:@github.com/.insteadOf https://github.com/ && \
    python3 -m pip install -q -r requirements_local_composer.txt && \
    python3 -m pip install -q -r requirements_test.txt --extra-index-url https://quintoandar.github.io/python-package-server/ && \
    python3 -m pip install -q -r requirements.txt && \
    git clone https://github.com/quintoandar/airflow-plugins.git && \
    locale-gen --purge pt_BR.UTF-8

COPY ./tests ./tests
COPY ./bietlejuice ./bietlejuice

RUN mkdir /bi-etl-ejuice/local/airflow/plugins/ \
    && cp -R ./airflow-plugins/quintoandar_airflow_plugins/* ./airflow/plugins \
    && rm -R ./airflow-plugins

CMD ["pytest", "-W", "ignore::DeprecationWarning", "--cov-fail-under=40", "tests/"]
