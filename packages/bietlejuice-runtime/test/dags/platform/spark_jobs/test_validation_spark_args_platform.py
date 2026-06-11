"""Argparse validation-flag smoke tests for standalone platform Spark jobs."""

import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[6]

_PLATFORM_JOB_PATHS = [
    "dags/platform/databricks_usage/spark_jobs/load_databricks_usage_raw.py",
    "dags/platform/enrich_spark_event_logs/spark_jobs/load_spark_stage_metrics.py",
]

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
from dags.platform.enrich_spark_event_logs.spark_jobs.load_spark_stage_metrics import (  # noqa: E402
    parse_args as parse_spark_stage_metrics,
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

_SPARK_STAGE_METRICS_POSITIONAL = [
    "prod",
    "5a-datalake-prod",
    "enrich_spark_event_logs",
    "databricks_health",
    "spark_stage_metrics",
    "2024-01-01",
    "2024-01-02",
    "5a-databricks-prod",
]

_VALIDATION_FLAGS = [
    "--target-database-name",
    "cluster_validation",
    "--target-table-name",
    "datalake_databricks___daily_users",
]

_SPARK_STAGE_METRICS_VALIDATION_FLAGS = [
    "--target-database-name",
    "cluster_validation",
    "--target-table-name",
    "datalake_databricks_health___spark_stage_metrics",
]


@pytest.mark.parametrize("job_path", _PLATFORM_JOB_PATHS)
def test_spark_job_registers_validation_write_flags(job_path: str):
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    assert "add_validation_target_args" in text or "--target-database-name" in text
    assert "resolve_datalake_write_target(" in text


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

    def test_spark_stage_metrics_accepts_validation_flags(self, monkeypatch):
        monkeypatch.setattr(
            sys,
            "argv",
            ["job"]
            + _SPARK_STAGE_METRICS_POSITIONAL
            + _SPARK_STAGE_METRICS_VALIDATION_FLAGS,
        )
        args = parse_spark_stage_metrics()

        assert args.target_database_name == "cluster_validation"
        assert (
            args.target_table_name == "datalake_databricks_health___spark_stage_metrics"
        )

    def test_spark_stage_metrics_defaults_without_validation_flags(self, monkeypatch):
        monkeypatch.setattr(sys, "argv", ["job"] + _SPARK_STAGE_METRICS_POSITIONAL)
        args = parse_spark_stage_metrics()

        assert args.target_database_name is None
        assert args.target_table_name is None
