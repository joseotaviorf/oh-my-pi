"""Shared PySpark fixtures for dw_agent_visit_funnel Spark job tests."""

import pytest
from pyspark.sql import SparkSession


@pytest.fixture(scope="module")
def spark():
    return (
        SparkSession.builder.appName("test_dw_agent_visit_funnel")
        .master("local[1]")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )
