FROM ubuntu:20.04

LABEL maintainer='Data Engineer Team'

ENV DEBIAN_FRONTEND=noninteractive

# Installing python3 and java
RUN apt update -yqq && \
    apt install --no-install-recommends -yqq software-properties-common default-jdk && \
    add-apt-repository ppa:deadsnakes/ppa -y && \
    add-apt-repository ppa:openjdk-r/ppa -y && \
    apt update && \
    apt install --no-install-recommends -yqq python3.7 python3.7-dev python3-pip openjdk-8-jdk && \
    python3.7 -m pip install pip==20.0.2

WORKDIR /bi-etl-ejuice

ENV PYTHONIOENCODING=utf-8 \
    AIRFLOW_HOME=/bi-etl-ejuice/airflow_python3 \
    PYTHONPATH=":/bi-etl-ejuice" \
    SLUGIFY_USES_TEXT_UNIDECODE=yes \
    AIRFLOW_GPL_UNIDECODE=yes \
    JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64/jre/" \ 
    PYSPARK_DRIVER_PYTHON=python3.7 \
    PYSPARK_PYTHON=python3.7

RUN apt update -yqq && \
    apt install --no-install-recommends -yqq \
    python3-setuptools \
    libpq-dev \
    libghc-persistent-postgresql-dev \
    build-essential \
    autoconf \
    libtool \
    libssl-dev \
    libffi-dev \
    git \
    jq \
    locales

RUN apt update -yqq && \
    apt install libmysqlclient-dev -yqq && \
    rm -rf /var/lib/apt/lists/*

COPY requirements3_local_composer.txt requirements3_local_extra.txt requirements3_local_internal.txt requirements3_test.txt ./

ARG GITHUB_TOKEN

RUN git config --global url.https://${GITHUB_TOKEN}:@github.com/.insteadOf https://github.com/ && \
    python3.7 -m pip install  --no-use-pep517 -q -r requirements3_local_composer.txt && \
    python3.7 -m pip install --no-use-pep517 -q -r requirements3_local_extra.txt && \
    python3.7 -m pip install --no-use-pep517 -q -r requirements3_local_internal.txt --extra-index-url https://quintoandar.github.io/python-package-server/ --no-deps && \
    python3.7 -m pip install --no-use-pep517 -q -r requirements3_test.txt && \
    git clone https://github.com/quintoandar/airflow-plugins.git && \
    locale-gen --purge pt_BR.UTF-8

COPY . .

RUN /bin/bash -c 'mkdir /bi-etl-ejuice/airflow_python3/plugins && cp -R /bi-etl-ejuice/airflow-plugins/quintoandar_airflow_plugins/* /bi-etl-ejuice/airflow_python3/plugins && rm -R /bi-etl-ejuice/airflow-plugins'

CMD ["pytest", "tests3/"]