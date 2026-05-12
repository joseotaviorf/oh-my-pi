import pytest

from bietlejuice.clients.db_clients.spark_client import SparkClient
from bietlejuice.consumers.db_consumers.databricks_consumer import DatabricksConsumer


@pytest.fixture()
def databricks_consumer():
    spark_client = SparkClient()
    return DatabricksConsumer(
        conn_config={"db": "<database_name>"}, spark_client=spark_client
    )
