import sys
from unittest.mock import MagicMock

import pytest

# Stub private packages that production code imports at module level but cannot
# be installed locally (VCS-only or Nexus-only; see pyproject.toml comments).
# This unblocks test collection without requiring a full private-package install.
_private_modules = [
    # inmetro – data-quality library (GitHub Pages VCS; own pyproject.toml has
    # a broken self-referential `-e` entry that uv cannot parse)
    "inmetro",
    "inmetro.builders",
    "inmetro.builders.validations",
    "inmetro.builders.validations.pydeequ",
    "inmetro.builders.validations.pydeequ.validation_suite_builder",
    "inmetro.clients",
    "inmetro.config_reader",
    "inmetro.loaders",
    "inmetro.validators",
    # edwiges is Nexus-only; cannot be installed locally
    "edwiges",
]

for _mod in _private_modules:
    sys.modules.setdefault(_mod, MagicMock())


@pytest.fixture(scope="session")
def spark_session():
    """Shared SparkSession for tests that need a real Spark context."""
    from bietlejuice.base.spark.base_spark import BaseSparkContext

    return BaseSparkContext.spark


@pytest.fixture(scope="session")
def spark(spark_session):
    """Alias for spark_session used by qube tests."""
    return spark_session


@pytest.fixture(scope="session")
def sample_dataframe(spark_session):
    """Small Spark DataFrame used by surrogate_keys tests (3 rows, id_entity + name)."""
    from pyspark.sql.types import StringType, StructField, StructType

    schema = StructType(
        [
            StructField("id_entity", StringType(), True),
            StructField("name", StringType(), True),
        ]
    )
    data = [("id_1", "name_1"), ("id_2", "name_2"), ("id_3", "name_3")]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture(scope="session")
def empty_dataframe(spark_session):
    """Empty Spark DataFrame with the same schema as sample_dataframe."""
    from pyspark.sql.types import StringType, StructField, StructType

    schema = StructType(
        [
            StructField("id_entity", StringType(), True),
            StructField("name", StringType(), True),
        ]
    )
    return spark_session.createDataFrame([], schema)
