FROM python:2.7.12
WORKDIR /opt/current-app
ENV PYTHONPATH $PYTHONPATH:/opt/current-app
ADD requirements.txt .
RUN pip install -r requirements.txt
ADD . .
ENTRYPOINT ["python"]
CMD ["--help"]
# docker run -it bi_etl ./tests/test_default.py
