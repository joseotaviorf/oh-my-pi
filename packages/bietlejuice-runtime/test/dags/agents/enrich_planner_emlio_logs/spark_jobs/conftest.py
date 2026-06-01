"""
Fixtures for load_planner_emlio_logs unit tests.

bietlejuice and quintoandar_logger are mocked before the source module is
imported so the tests run in CI without those libraries being installed.
PySpark 3.3.2 with a local[1] Spark session is used for all DataFrame tests
(same Docker image — octoenergy/pyspark:3.3.2 — that CI uses).
"""

import json
import os
import sys
from unittest.mock import MagicMock

# Ensure Spark workers use the same Python interpreter as the test driver.
# Without this, workers default to the system python (potentially a different
# version), causing "Python in worker has different version" errors.
os.environ.setdefault("PYSPARK_PYTHON", sys.executable)

import pytest

_BIETLEJUICE_MOCKS = [
    "bietlejuice",
    "bietlejuice.base",
    "bietlejuice.base.databricks",
    "bietlejuice.base.databricks.table_privileges",
    "bietlejuice.base.db",
    "bietlejuice.base.spark",
    "bietlejuice.base.spark.unity_catalog_helper",
    "bietlejuice.base.validation",
    "bietlejuice.base.validation.spark_args",
    "bietlejuice.clients",
    "bietlejuice.clients.db_clients",
    "bietlejuice.loaders",
    "bietlejuice.loaders.delta_loader",
    "bietlejuice.services",
    "bietlejuice.services.metastore_services",
    "quintoandar_logger",
]
for _mod in _BIETLEJUICE_MOCKS:
    sys.modules.setdefault(_mod, MagicMock())


@pytest.fixture(scope="session")
def spark():
    from pyspark.sql import SparkSession

    session = (
        SparkSession.builder.appName("test_planner_emlio_logs")
        .master("local[1]")
        .config("spark.sql.shuffle.partitions", "1")
        .config("spark.driver.bindAddress", "127.0.0.1")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )
    yield session
    session.stop()


def _source_schema():
    from pyspark.sql.types import IntegerType, StringType, StructField, StructType

    return StructType(
        [
            StructField("uuid", StringType()),
            StructField("inputs", StringType()),
            StructField("outputs", StringType()),
            StructField("year", IntegerType()),
            StructField("month", IntegerType()),
            StructField("day", IntegerType()),
        ]
    )


SAMPLE_INPUTS = json.dumps(
    {"planner_agent_request": {"business_context": "for_rent", "id_house": 1001}}
)

SAMPLE_OUTPUTS = json.dumps(
    {
        "shadow_mode_response": {"agents": [101, 102], "group": "group_A"},
        "shadow_mode_observability_data": {"strategy_type_used": "ml"},
    }
)


@pytest.fixture(scope="session")
def source_df(spark):
    return spark.createDataFrame(
        [("uuid-1", SAMPLE_INPUTS, SAMPLE_OUTPUTS, 2026, 4, 1)],
        _source_schema(),
    )
