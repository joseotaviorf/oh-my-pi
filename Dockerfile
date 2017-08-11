FROM python:2

WORKDIR /opt/current-app

ENV PYTHONPATH $PYTHONPATH:/opt/current-app

ADD . .

RUN pip install --upgrade pip
RUN pip install -r dependency_requirements.txt
RUN pip install -r requirements.txt
RUN pip install git+git://github.com/quintoandar/python-utils.git

ENTRYPOINT ["python"]

CMD ["--help"]

# docker run -it bi_etl ./tests/test_default.py