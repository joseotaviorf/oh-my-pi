import pytest

from bietlejuice.consumers.db_consumers.postgres_consumer import PostgresConsumer
from bietlejuice.clients.db_clients.spark_client import SparkClient


@pytest.fixture()
def postgres_consumer():
    spark_client = SparkClient()
    return PostgresConsumer(
        conn_config={
            "dbtype": "postgres",
            "host": "localhost",
            "port": "5432",
            "db": "<database_name>",
            "user": "<database_user>",
            "pwd": "<database_password>",
            "schema": "public",
        },
        spark_client=spark_client,
    )
