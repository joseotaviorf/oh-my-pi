"""Argparse validation-flag smoke tests for standalone platform Spark jobs."""

import sys
from unittest.mock import MagicMock

import pytest

_SPARK_STUBS = [
    "pyspark",
    "pyspark.sql",
    "pyspark.sql.functions",
    "pyspark.sql.types",
    "pyspark.sql.dataframe",
    "databricks",
    "databricks.sdk",
    "quintoandar_logger",
    "bietlejuice.loaders.delta_loader",
    "bietlejuice.services.configuration_service",
    "bietlejuice.base.spark",
    "bietlejuice.base.spark.base_spark",
    "bietlejuice.clients.db_clients",
    "bietlejuice.services.metastore_services",
    "bietlejuice.loaders",
    "bietlejuice.loaders.s3_loader",
    "bietlejuice.pipeline",
    "hierarchical_conf",
    "hierarchical_conf.hierarchical_conf",
    "boto3",
]
for _mod in _SPARK_STUBS:
    sys.modules.setdefault(_mod, MagicMock())

from dags.platform.enrich_databricks.spark_jobs.load_daily_users import (  # noqa: E402
    parse_args as parse_daily_users,
)
from dags.platform.enrich_databricks.spark_jobs.load_instance_pools import (  # noqa: E402
    parse_args as parse_instance_pools,
)

_DAILY_USERS_POSITIONAL = [
    "prod",
    "5a-datalake-prod",
    "enrich_databricks",
    "databricks",
    "daily_users",
    '["year", "month", "day"]',
]

_INSTANCE_POOLS_POSITIONAL = [
    "prod",
    "5a-datalake-prod",
    "enrich_databricks",
    "databricks",
    "instance_pools",
]

_VALIDATION_FLAGS = [
    "--target-database-name",
    "cluster_validation",
    "--target-table-name",
    "datalake_databricks___daily_users",
]


class TestPlatformSparkJobValidationArgs:
    @pytest.mark.parametrize(
        "parse_fn,positional",
        [
            (parse_daily_users, _DAILY_USERS_POSITIONAL),
            (parse_instance_pools, _INSTANCE_POOLS_POSITIONAL),
        ],
    )
    def test_accepts_validation_flags(self, parse_fn, positional, monkeypatch):
        monkeypatch.setattr(sys, "argv", ["job"] + positional + _VALIDATION_FLAGS)
        args = parse_fn()

        assert args.target_database_name == "cluster_validation"
        assert args.target_table_name == "datalake_databricks___daily_users"

    @pytest.mark.parametrize(
        "parse_fn,positional",
        [
            (parse_daily_users, _DAILY_USERS_POSITIONAL),
            (parse_instance_pools, _INSTANCE_POOLS_POSITIONAL),
        ],
    )
    def test_defaults_without_validation_flags(self, parse_fn, positional, monkeypatch):
        monkeypatch.setattr(sys, "argv", ["job"] + positional)
        args = parse_fn()

        assert args.target_database_name is None
        assert args.target_table_name is None
