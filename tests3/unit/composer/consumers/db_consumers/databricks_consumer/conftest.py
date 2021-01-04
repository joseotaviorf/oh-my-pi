import pytest

from bietlejuice.jobs.composer.consumers.db_consumers.databricks_consumer import (
    DatabricksConsumer,
)
from bietlejuice.jobs.composer.clients.db_clients.spark_client import SparkClient


@pytest.fixture()
def databricks_consumer():
    spark_client = SparkClient()
    return DatabricksConsumer(
        conn_config={"db": "<database_name>"}, spark_client=spark_client
    )
