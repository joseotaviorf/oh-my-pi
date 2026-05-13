"""Unit tests for pure helpers in load_offboarding_categorization_raw.

The Spark / logger / bietlejuice dependencies are mocked **only during the
import** of the module under test, via ``patch.dict("sys.modules", ...)`` used
as a context manager. ``patch.dict`` snapshots ``sys.modules`` on enter and
fully restores it on exit, so the real PySpark and ``quintoandar_logger``
modules remain untouched for every other test in the same pytest run
(prevents the leak that previously broke ~79 tests in cdf_services / qube /
metastore by leaving ``MagicMock`` objects in place of the real libraries).
"""

import importlib.util
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

_SPARK_JOB_PATH = (
    Path(__file__).resolve().parents[6]
    / "dags/for_rent/offboarding_categorization/spark_jobs"
    / "load_offboarding_categorization_raw.py"
)

_IMPORT_TIME_MOCKS = {
    "pyspark": MagicMock(),
    "pyspark.sql": MagicMock(),
    "pyspark.sql.functions": MagicMock(),
    "bietlejuice.base.db": MagicMock(),
    "bietlejuice.base.spark": MagicMock(),
    "bietlejuice.clients.db_clients": MagicMock(),
    "bietlejuice.consumers.s3_consumer": MagicMock(),
    "bietlejuice.loaders": MagicMock(),
    "bietlejuice.loaders.s3_loader": MagicMock(),
    "bietlejuice.services.metastore_services": MagicMock(),
    "quintoandar_logger": MagicMock(),
}

with patch.dict("sys.modules", _IMPORT_TIME_MOCKS):
    _spec = importlib.util.spec_from_file_location(
        "load_offboarding_categorization_raw", _SPARK_JOB_PATH
    )
    _job = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_job)

build_session_metadata_parquet_uri = _job.build_session_metadata_parquet_uri
get_forno_adjusted_data_science_path = _job.get_forno_adjusted_data_science_path
inclusive_calendar_days = _job.inclusive_calendar_days


def test_get_forno_adjusted_data_science_path_prod_unchanged():
    uri = "s3://data-science.s3.data.quintoandar.com.br/chatbot/x"
    assert get_forno_adjusted_data_science_path("prod", uri) == uri


def test_get_forno_adjusted_data_science_path_forno_swap():
    uri = "s3://data-science.s3.data.quintoandar.com.br/chatbot/x"
    assert (
        get_forno_adjusted_data_science_path("forno", uri)
        == "s3://data-science.s3.forno.data.quintoandar.com.br/chatbot/x"
    )


def test_build_session_metadata_parquet_uri():
    base = (
        "s3://data-science.s3.data.quintoandar.com.br/chatbot/wall-e/session-metadata"
    )
    assert (
        build_session_metadata_parquet_uri(base, "2026-03-11")
        == f"{base}/2026-03-11.parquet"
    )
    assert (
        build_session_metadata_parquet_uri(f"{base}/", "2026-03-11")
        == f"{base}/2026-03-11.parquet"
    )


def test_inclusive_calendar_days_single_day():
    assert inclusive_calendar_days("2026-03-10", "2026-03-10") == ["2026-03-10"]


def test_inclusive_calendar_days_multiple():
    assert inclusive_calendar_days("2026-03-09", "2026-03-11") == [
        "2026-03-09",
        "2026-03-10",
        "2026-03-11",
    ]


def test_inclusive_calendar_days_start_after_end_raises():
    with pytest.raises(ValueError, match="must be <="):
        inclusive_calendar_days("2026-03-12", "2026-03-10")
