"""
Pytest fixtures for QUBE unit tests.
"""

import pytest
from pyspark.sql import SparkSession


@pytest.fixture(scope="session")
def spark():
    """
    Create a Spark session for QUBE testing.

    This fixture is needed because QUBE modules import Spark dependencies
    during module load time, even though the unit tests mock most functionality.
    """
    spark = (
        SparkSession.builder.appName("QubeTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "false")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()
