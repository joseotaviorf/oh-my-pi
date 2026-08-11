"""Spark session and module mocks for monalisa_monitoria_evaluations spark job tests.

The job imports Databricks-side bietlejuice modules at import time; mock them so the pure
transform functions can be imported and exercised against a local SparkSession.
"""

import os
import sys
from unittest.mock import MagicMock

import pytest

_BIETLEJUICE_MOCKS = [
    "bietlejuice",
    "bietlejuice.base",
    "bietlejuice.base.db",
    "bietlejuice.base.pipeline",
    "bietlejuice.base.pipeline.layer_enum",
    "bietlejuice.base.spark",
    "bietlejuice.base.validation",
    "bietlejuice.base.validation.spark_args",
    "bietlejuice.loaders",
    "bietlejuice.loaders.delta_loader",
    "bietlejuice.services",
    "bietlejuice.services.configuration_service",
    "quintoandar_logger",
]
for _mod in _BIETLEJUICE_MOCKS:
    sys.modules.setdefault(_mod, MagicMock())

os.environ.setdefault("PYSPARK_PYTHON", sys.executable)


@pytest.fixture(scope="session")
def spark():
    pytest.importorskip("pyspark")
    from pyspark.sql import SparkSession

    session = (
        SparkSession.builder.appName("test_monalisa_monitoria_evaluations_load")
        .master("local[1]")
        .config("spark.sql.shuffle.partitions", "1")
        .config("spark.driver.bindAddress", "127.0.0.1")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )
    yield session
    session.stop()
