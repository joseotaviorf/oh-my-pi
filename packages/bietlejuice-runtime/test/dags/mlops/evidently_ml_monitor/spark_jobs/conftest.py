"""Spark session and module mocks for evidently_ml_monitor spark job tests."""

import os
import sys
from unittest.mock import MagicMock

import pytest

_BIETLEJUICE_MOCKS = [
    "bietlejuice",
    "bietlejuice.base",
    "bietlejuice.base.db",
    "bietlejuice.base.spark",
    "bietlejuice.clients",
    "bietlejuice.clients.db_clients",
    "bietlejuice.loaders",
    "bietlejuice.loaders.s3_loader",
    "bietlejuice.services",
    "bietlejuice.services.configuration_service",
    "bietlejuice.services.metastore_services",
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
        SparkSession.builder.appName("test_evidently_ml_monitor_raw")
        .master("local[1]")
        .config("spark.sql.shuffle.partitions", "1")
        .config("spark.driver.bindAddress", "127.0.0.1")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )
    yield session
    session.stop()
