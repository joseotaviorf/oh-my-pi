FROM python:2.7.12

LABEL maintainer='Data Engineer Team'

WORKDIR /bi-etl-ejuice

# Airflow
# Env variables for Airflow
ARG AIRFLOW_VERSION=1.10.2
ENV PYTHONIOENCODING=utf-8 \
    AIRFLOW_HOME=/bi-etl-ejuice/airflow_python2 \
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
    locales

ARG GITHUB_TOKEN

# This step will be improve with a new step that get your github authentication from your machine.
# Until there, let's use this primitive way :D
RUN git config --global url.https://${GITHUB_TOKEN}:@github.com/.insteadOf https://github.com/ && \
    python2 -m pip install --upgrade pip && \
    locale-gen --purge pt_BR.UTF-8

COPY requirements.txt .

RUN pip install -r requirements.txt --extra-index-url https://quintoandar.github.io/python-package-server/

COPY . .

RUN chmod +x start.sh

ENTRYPOINT /bi-etl-ejuice/start.sh

EXPOSE 8080