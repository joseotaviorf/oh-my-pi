"""
Pytest fixtures for core_brokers Spark job tests.
"""

import pytest
from pyspark.sql import SparkSession


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (
        SparkSession.builder.appName("CoreBrokersTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()
