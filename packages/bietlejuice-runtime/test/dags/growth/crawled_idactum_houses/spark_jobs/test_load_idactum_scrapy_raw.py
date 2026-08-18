"""Unit tests for load_idactum_scrapy_raw skip/bootstrap behavior."""

import importlib.util
import sys
import types
from datetime import date
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest


# Minimal PySpark type stubs so unit-tests-dags can import the job without a cluster.
class _StringType:
    pass


class _LongType:
    pass


class _ArrayType:
    def __init__(self, elementType, containsNull=True):
        self.elementType = elementType
        self.containsNull = containsNull


class _StructField:
    def __init__(self, name, dataType, nullable=True):
        self.name = name
        self.dataType = dataType
        self.nullable = nullable


class _StructType:
    def __init__(self, fields):
        self.fields = fields


class _AnalysisException(Exception):
    pass


_pyspark_sql_types = types.ModuleType("pyspark.sql.types")
_pyspark_sql_types.ArrayType = _ArrayType
_pyspark_sql_types.LongType = _LongType
_pyspark_sql_types.StringType = _StringType
_pyspark_sql_types.StructField = _StructField
_pyspark_sql_types.StructType = _StructType

_pyspark_sql_utils = types.ModuleType("pyspark.sql.utils")
_pyspark_sql_utils.AnalysisException = _AnalysisException

sys.modules.setdefault("pyspark", MagicMock())
sys.modules.setdefault("pyspark.sql", MagicMock())
sys.modules.setdefault("pyspark.sql.functions", MagicMock())
sys.modules.setdefault("pyspark.sql.types", _pyspark_sql_types)
sys.modules.setdefault("pyspark.sql.utils", _pyspark_sql_utils)

_SPARK_JOB_PATH = (
    Path(__file__).resolve().parents[7]
    / "dags/growth/crawled_idactum_houses/spark_jobs/load_idactum_scrapy_raw.py"
)

_IMPORT_TIME_MOCKS = {
    "bietlejuice.base.databricks.table_privileges": MagicMock(),
    "bietlejuice.base.db": MagicMock(),
    "bietlejuice.base.spark": MagicMock(),
    "bietlejuice.base.spark.unity_catalog_helper": MagicMock(),
    "bietlejuice.clients.db_clients": MagicMock(),
    "bietlejuice.consumers.s3_consumer": MagicMock(),
    "bietlejuice.loaders": MagicMock(),
    "bietlejuice.loaders.s3_loader": MagicMock(),
    "bietlejuice.services.configuration_service": MagicMock(),
    "bietlejuice.services.metastore_services": MagicMock(),
    "quintoandar_logger": MagicMock(),
}


def _load_job_module():
    with patch.dict("sys.modules", _IMPORT_TIME_MOCKS):
        spec = importlib.util.spec_from_file_location(
            "load_idactum_scrapy_raw", _SPARK_JOB_PATH
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module


@pytest.fixture(scope="module")
def job():
    return _load_job_module()


def test_is_missing_feed_error_matches_path_not_found(job):
    exc = Exception("Path does not exist: s3://bucket/missing")
    assert job._is_missing_feed_error(exc) is True


def test_is_missing_feed_error_does_not_match_unrelated(job):
    assert job._is_missing_feed_error(Exception("table not found")) is False


def test_empty_raw_schema_defaults_to_response_struct(job):
    schema = job._empty_raw_schema("rj_itbi_main")
    field_names = {field.name for field in schema.fields}
    assert field_names == {"response", "metadata"}


def test_empty_raw_schema_osasco_pesquisa_cdc_uses_array_response(job):
    schema = job._empty_raw_schema("sp_osasco_pesquisa_cdc")
    response_field = next(field for field in schema.fields if field.name == "response")
    assert isinstance(response_field.dataType, _ArrayType)


def test_empty_raw_schema_informacoes_cadastrais_has_top_level_fields(job):
    schema = job._empty_raw_schema("go_goiania_informacoes_cadastrais")
    field_names = {field.name for field in schema.fields}
    assert field_names == {
        "registration_number",
        "cadastral_info",
        "total_records",
        "metadata",
    }


def test_bootstrap_empty_raw_table_persists_empty_table(job):
    logger = MagicMock()
    empty_df = MagicMock(name="empty_df")
    transformed_df = MagicMock(name="transformed_df")

    with (
        patch.object(job, "_empty_raw_dataframe", return_value=empty_df) as empty_raw,
        patch.object(job, "transform_data", return_value=transformed_df) as transform,
        patch.object(job, "save_to_datalake") as save_to_datalake,
    ):
        job.bootstrap_empty_raw_table(
            logger,
            environment="forno",
            datalake_bucket="s3://bucket",
            table_name="sp_osasco_pesquisa_cdc",
            source="crawled_idactum_houses",
            spider="sp_osasco_pesquisa_cdc",
            execution_date=date(2026, 8, 1),
            ingestion_path="s3://crawler-scrapy-forno/sp_osasco_pesquisa_cdc/2026-08-01/*/batch_*.jsonl",
            reason="missing_feed_path",
            error=Exception("Path does not exist"),
        )

    empty_raw.assert_called_once_with("sp_osasco_pesquisa_cdc")
    transform.assert_called_once_with(
        empty_df,
        crawler_name="sp_osasco_pesquisa_cdc",
        execution_date=date(2026, 8, 1),
    )
    save_to_datalake.assert_called_once_with(
        dataframe=transformed_df,
        environment="forno",
        datalake_bucket="s3://bucket",
        table_name="sp_osasco_pesquisa_cdc",
        source="crawled_idactum_houses",
    )
