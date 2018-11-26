FROM python:2.7.12

WORKDIR /opt/current-app

ENV PYTHONPATH $PYTHONPATH:/opt/current-app \
    AIRFLOW_GPL_UNIDECODE=yes \
    SLUGIFY_USES_TEXT_UNIDECODE=yes

ADD requirements.txt .

RUN pip install --upgrade pip \
    && pip install -r requirements.txt

ADD . .

ENTRYPOINT ["python"]
