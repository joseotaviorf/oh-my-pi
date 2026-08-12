"""Pure-function unit tests for the Tars Vector logs raw load job.

No Spark/Databricks runtime required: pyspark and bietlejuice modules are mocked
in ``sys.modules`` before importing the module under test.
"""

import sys
from unittest.mock import MagicMock

import pytest

sys.modules.setdefault("pyspark", MagicMock())
sys.modules.setdefault("pyspark.sql", MagicMock())
sys.modules.setdefault("pyspark.sql.functions", MagicMock())
sys.modules.setdefault("pyspark.sql.window", MagicMock())
sys.modules.setdefault("quintoandar_logger", MagicMock())
sys.modules.setdefault("bietlejuice.base.db", MagicMock())
sys.modules.setdefault("bietlejuice.base.spark", MagicMock())
sys.modules.setdefault("bietlejuice.base.validation.spark_args", MagicMock())
sys.modules.setdefault("bietlejuice.clients.db_clients", MagicMock())
sys.modules.setdefault("bietlejuice.loaders", MagicMock())
sys.modules.setdefault("bietlejuice.loaders.s3_loader", MagicMock())
sys.modules.setdefault("bietlejuice.services.configuration_service", MagicMock())
sys.modules.setdefault("bietlejuice.services.metastore_services", MagicMock())

from dags.governance.tars_vector_logs.spark_jobs.load_incremental_tars_vector_logs_raw import (  # noqa: E402
    build_day_glob,
    inclusive_calendar_days,
)


class TestInclusiveCalendarDays:
    def test_single_day(self):
        assert inclusive_calendar_days("2026-08-12", "2026-08-12") == ["2026-08-12"]

    def test_inclusive_range(self):
        assert inclusive_calendar_days("2026-08-12", "2026-08-14") == [
            "2026-08-12",
            "2026-08-13",
            "2026-08-14",
        ]

    def test_start_after_end_raises(self):
        with pytest.raises(ValueError, match="must be <="):
            inclusive_calendar_days("2026-08-15", "2026-08-12")


class TestBuildDayGlob:
    def test_builds_utc_day_glob(self):
        assert (
            build_day_glob("5a-tars-prod-data", "tars-logs", "2026-08-12")
            == "s3://5a-tars-prod-data/tars-logs/2026/08/12/*/*.log.gz"
        )

    def test_strips_trailing_slash_on_folder(self):
        assert (
            build_day_glob("5a-tars-forno-forno-data", "tars-logs/", "2026-01-05")
            == "s3://5a-tars-forno-forno-data/tars-logs/2026/01/05/*/*.log.gz"
        )
