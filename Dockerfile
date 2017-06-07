FROM ubuntu:latest

WORKDIR /opt/current-app

ENV PYTHONPATH $PYTHONPATH:/opt/current-app

ADD . .

# Java 8
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y software-properties-common && \
    add-apt-repository ppa:webupd8team/java -y && \
    apt-get update && \
    echo oracle-java7-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections && \
    apt-get install -y oracle-java8-installer && \
    apt-get clean && \
    apt-get install -y libpq-dev python-dev

RUN apt-get -y install python-pip python-dev build-essential

RUN pip install --upgrade pip
RUN pip install -r requirements.txt

ENTRYPOINT ["python"]

CMD ["--help"]

# docker run -it bi_etl ./tests/test_default.py