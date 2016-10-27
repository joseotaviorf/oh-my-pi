FROM python:2

WORKDIR /opt/current-app

ENV PYTHONPATH $PYTHONPATH:/opt/current-app

ADD . .

RUN pip install -r requirements.txt

ENTRYPOINT ["python"]

CMD ["--help"]

# docker run -it bi_etl ./tests/test_default.py