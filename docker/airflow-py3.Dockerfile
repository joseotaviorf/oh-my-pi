FROM python:3.6.10-slim

LABEL maintainer='Data Engineer Team'

WORKDIR /bi-etl-ejuice

ENV PYTHONIOENCODING=utf-8 \
    AIRFLOW_HOME=/bi-etl-ejuice/airflow_python3 \
    PYTHONPATH=":/bi-etl-ejuice" \
    SLUGIFY_USES_TEXT_UNIDECODE=yes \
    AIRFLOW_GPL_UNIDECODE=yes

RUN apt-get update -yqq && \
    apt-get install -yqq \
    python-pip \
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

COPY requirements3_local_composer.txt requirements3_local_extra.txt requirements3_local_internal.txt  ./

ARG GITHUB_TOKEN

# This step will be improve with a new step that get your github authentication from your machine.
# Until there, let's use this primitive way :D
RUN python3 -m pip install -q --upgrade pip && \
    git config --global url.https://${GITHUB_TOKEN}:@github.com/.insteadOf https://github.com/ && \
    pip install -q -r requirements3_local_composer.txt && \
    pip install -q -r requirements3_local_extra.txt && \
    pip install -q -r requirements3_local_internal.txt --extra-index-url https://quintoandar.github.io/python-package-server/ --no-deps && \
    git clone https://github.com/quintoandar/airflow-plugins.git && \
    locale-gen --purge pt_BR.UTF-8

COPY . .

RUN chmod +x start.sh && \
    /bin/bash -c 'mkdir /bi-etl-ejuice/airflow_python3/plugins && cp -R /bi-etl-ejuice/airflow-plugins/quintoandar_airflow_plugins/* /bi-etl-ejuice/airflow_python3/plugins && rm -R /bi-etl-ejuice/airflow-plugins'

ENTRYPOINT ["/bin/bash", "-c", "/bi-etl-ejuice/start.sh"]
