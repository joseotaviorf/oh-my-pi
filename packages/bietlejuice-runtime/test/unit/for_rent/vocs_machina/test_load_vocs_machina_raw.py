"""Unit tests for pure helpers in load_vocs_machina_raw.

Heavy Spark/bietlejuice deps are mocked at import-time via patch.dict so the
real libraries are not affected for other tests in the same pytest run.
"""

import importlib.util
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

_SPARK_JOB_PATH = (
    Path(__file__).resolve().parents[6]
    / "dags/for_rent/vocs_machina/spark_jobs"
    / "load_vocs_machina_raw.py"
)

_IMPORT_TIME_MOCKS = {
    "pyspark": MagicMock(),
    "pyspark.sql": MagicMock(),
    "pyspark.sql.functions": MagicMock(),
    "pyspark.sql.types": MagicMock(LongType=type("LongType", (), {})),
    "pyspark.sql.window": MagicMock(),
    "bietlejuice.base.db": MagicMock(),
    "bietlejuice.base.spark": MagicMock(),
    "bietlejuice.base.validation.spark_args": MagicMock(),
    "bietlejuice.clients.db_clients": MagicMock(),
    "bietlejuice.consumers.s3_consumer": MagicMock(),
    "bietlejuice.loaders": MagicMock(),
    "bietlejuice.loaders.s3_loader": MagicMock(),
    "bietlejuice.services.metastore_services": MagicMock(),
    "quintoandar_logger": MagicMock(),
}

with patch.dict("sys.modules", _IMPORT_TIME_MOCKS):
    _spec = importlib.util.spec_from_file_location(
        "load_vocs_machina_raw", _SPARK_JOB_PATH
    )
    _job = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_job)

get_forno_adjusted_data_science_path = _job.get_forno_adjusted_data_science_path
build_day_partition_uri = _job.build_day_partition_uri
inclusive_calendar_days = _job.inclusive_calendar_days
_prepare_day_df = _job._prepare_day_df
PERSISTED_COLUMNS = _job.PERSISTED_COLUMNS
F = _job.F


def test_get_forno_adjusted_data_science_path_prod_unchanged():
    uri = "s3://data-science.s3.data.quintoandar.com.br/post-contract/vocs-machina"
    assert get_forno_adjusted_data_science_path("prod", uri) == uri


def test_get_forno_adjusted_data_science_path_staging_unchanged():
    uri = "s3://data-science.s3.data.quintoandar.com.br/post-contract/vocs-machina"
    assert get_forno_adjusted_data_science_path("staging", uri) == uri


def test_get_forno_adjusted_data_science_path_forno_swap():
    uri = "s3://data-science.s3.data.quintoandar.com.br/post-contract/vocs-machina"
    assert (
        get_forno_adjusted_data_science_path("forno", uri)
        == "s3://data-science.s3.forno.data.quintoandar.com.br/post-contract/vocs-machina"
    )


def test_build_day_partition_uri_format():
    base = "s3://data-science.s3.data.quintoandar.com.br/post-contract/vocs-machina"
    assert (
        build_day_partition_uri(base, "2026-06-11")
        == f"{base}/raw/year=2026/month=06/day=11"
    )


def test_build_day_partition_uri_strips_trailing_slash():
    base = "s3://data-science.s3.data.quintoandar.com.br/post-contract/vocs-machina/"
    assert (
        build_day_partition_uri(base, "2026-06-01")
        == "s3://data-science.s3.data.quintoandar.com.br/post-contract/vocs-machina/raw/year=2026/month=06/day=01"
    )


def test_build_day_partition_uri_zero_pads_month_and_day():
    base = "s3://bucket/vocs"
    assert (
        build_day_partition_uri(base, "2026-02-05")
        == f"{base}/raw/year=2026/month=02/day=05"
    )


def test_inclusive_calendar_days_single_day():
    assert inclusive_calendar_days("2026-06-10", "2026-06-10") == ["2026-06-10"]


def test_inclusive_calendar_days_multiple():
    assert inclusive_calendar_days("2026-06-09", "2026-06-11") == [
        "2026-06-09",
        "2026-06-10",
        "2026-06-11",
    ]


def test_inclusive_calendar_days_start_after_end_raises():
    with pytest.raises(ValueError, match="must be <="):
        inclusive_calendar_days("2026-06-12", "2026-06-10")


def test_prepare_day_df_sets_partition_cols_from_load_date():
    df = MagicMock()
    df.columns = list(PERSISTED_COLUMNS)
    selected = MagicMock()
    selected.columns = list(PERSISTED_COLUMNS)
    df.select.return_value = selected
    with_ts = MagicMock()
    selected.withColumn.return_value = with_ts
    with_year = MagicMock()
    with_month = MagicMock()
    with_day = MagicMock()
    with_ts.withColumn.return_value = with_year
    with_year.withColumn.return_value = with_month
    with_month.withColumn.return_value = with_day

    result = _prepare_day_df(df, "2026-06-11")

    df.select.assert_called_once_with(*PERSISTED_COLUMNS)
    selected.withColumn.assert_called_once_with("ts_load", F.current_timestamp())
    with_ts.withColumn.assert_called_once_with("year", F.lit(2026))
    with_year.withColumn.assert_called_once_with("month", F.lit(6))
    with_month.withColumn.assert_called_once_with("day", F.lit(11))
    assert result is with_day


def test_prepare_day_df_missing_columns_raises():
    df = MagicMock()
    df.columns = ["feedback_id"]

    with pytest.raises(ValueError, match="missing expected columns"):
        _prepare_day_df(df, "2026-06-11")


def _add_validation_target_args(parser):
    parser.add_argument("--target-database-name", required=False, default=None)
    parser.add_argument("--target-table-name", required=False, default=None)


def test_main_uses_validation_target_for_all_writes():
    spark_client = MagicMock()
    s3_consumer = MagicMock()
    s3_loader = MagicMock()
    spark_metastore_service = MagicMock()
    spark_metastore_loader = MagicMock()
    day_df = MagicMock()
    day_df.rdd.isEmpty.return_value = False

    argv = [
        "load_vocs_machina_raw",
        "prod",
        "prod-bucket",
        "vocs_machina",
        "s3://data-science.s3.data.quintoandar.com.br/post-contract/vocs-machina",
        "2026-06-11",
        "2026-06-11",
        "vocs_machina",
        "['year','month','day']",
        "parquet",
        "--target-database-name",
        "cluster_validation",
        "--target-table-name",
        "validation_vocs_machina",
    ]

    with (
        patch("sys.argv", argv),
        patch.object(
            _job,
            "add_validation_target_args",
            side_effect=_add_validation_target_args,
        ),
        patch.object(
            _job,
            "resolve_datalake_write_target",
            return_value=(
                "cluster_validation",
                "validation_vocs_machina",
                "s3://prod-bucket/cluster_validation/datalake_vocs_machina_raw/",
            ),
        ),
        patch.object(
            _job.DatalakeMetastoreService,
            "get_db_info",
            return_value={
                "db_raw_databricks": "datalake_vocs_machina_raw",
                "db_raw_path": "s3://prod-bucket/prod/datalake_vocs_machina_raw/",
            },
        ),
        patch.object(_job, "SparkClient", return_value=spark_client),
        patch.object(_job, "S3Consumer", return_value=s3_consumer),
        patch.object(_job, "S3Loader", return_value=s3_loader),
        patch.object(
            _job, "SparkMetastoreService", return_value=spark_metastore_service
        ),
        patch.object(_job, "SparkMetastoreLoader", return_value=spark_metastore_loader),
        patch.object(_job, "_prepare_day_df", return_value=day_df),
        patch.object(_job, "_dedup_df", return_value=day_df),
    ):
        _job.main()

    expected_partitions = ["year", "month", "day"]
    expected_write_location = (
        "s3://prod-bucket/cluster_validation/datalake_vocs_machina_raw/"
    )

    spark_metastore_service.create_database.assert_called_once_with(
        "cluster_validation"
    )
    s3_loader.load_df.assert_called_once_with(
        df=day_df,
        s3_path=f"{expected_write_location}validation_vocs_machina",
        format_options=_job.SparkTableStorageFormat.PARQUET,
        partitions=expected_partitions,
    )
    spark_metastore_loader.update_metastore.assert_called_once_with(
        df=day_df,
        database_name="cluster_validation",
        table_name="validation_vocs_machina",
        format_options=_job.SparkTableStorageFormat.PARQUET,
        database_location=expected_write_location,
        partitions=expected_partitions,
    )
    spark_metastore_service.create_new_partitions_from_df.assert_called_once_with(
        df=day_df,
        database_name="cluster_validation",
        table_name="validation_vocs_machina",
        partition_cols=expected_partitions,
    )


def test_main_no_data_table_not_exists_raises():
    """No S3 data + table never created → RuntimeError, no writes attempted."""
    spark_client = MagicMock()
    spark_client.conn.catalog.tableExists.return_value = False
    s3_consumer = MagicMock()
    s3_consumer.get_data_from_file.side_effect = Exception(
        "Path does not exist: s3://bucket/vocs-machina/raw/year=2026/month=07/day=07"
    )
    s3_loader = MagicMock()
    spark_metastore_service = MagicMock()
    spark_metastore_loader = MagicMock()

    argv = [
        "load_vocs_machina_raw",
        "prod",
        "prod-bucket",
        "vocs_machina",
        "s3://data-science.s3.data.quintoandar.com.br/post-contract/vocs-machina",
        "2026-07-07",
        "2026-07-07",
        "vocs_machina",
        "['year','month','day']",
        "parquet",
    ]

    with (
        patch("sys.argv", argv),
        patch.object(
            _job, "add_validation_target_args", side_effect=_add_validation_target_args
        ),
        patch.object(
            _job,
            "resolve_datalake_write_target",
            return_value=(
                "datalake_vocs_machina_raw",
                "vocs_machina",
                "s3://prod-bucket/prod/datalake_vocs_machina_raw/",
            ),
        ),
        patch.object(
            _job.DatalakeMetastoreService,
            "get_db_info",
            return_value={
                "db_raw_databricks": "datalake_vocs_machina_raw",
                "db_raw_path": "s3://prod-bucket/prod/datalake_vocs_machina_raw/",
            },
        ),
        patch.object(_job, "SparkClient", return_value=spark_client),
        patch.object(_job, "S3Consumer", return_value=s3_consumer),
        patch.object(_job, "S3Loader", return_value=s3_loader),
        patch.object(
            _job, "SparkMetastoreService", return_value=spark_metastore_service
        ),
        patch.object(_job, "SparkMetastoreLoader", return_value=spark_metastore_loader),
    ):
        with pytest.raises(RuntimeError, match="does not yet exist"):
            _job.main()

    s3_loader.load_df.assert_not_called()
    spark_metastore_loader.update_metastore.assert_not_called()


def test_main_no_data_table_exists_skips_gracefully():
    """No S3 data, but table already initialised → returns cleanly without writing."""
    spark_client = MagicMock()
    spark_client.conn.catalog.tableExists.return_value = True
    s3_consumer = MagicMock()
    s3_consumer.get_data_from_file.side_effect = Exception(
        "PATH_NOT_FOUND: s3://bucket/vocs-machina/raw/year=2026/month=07/day=07"
    )
    s3_loader = MagicMock()
    spark_metastore_service = MagicMock()
    spark_metastore_loader = MagicMock()

    argv = [
        "load_vocs_machina_raw",
        "prod",
        "prod-bucket",
        "vocs_machina",
        "s3://data-science.s3.data.quintoandar.com.br/post-contract/vocs-machina",
        "2026-07-07",
        "2026-07-07",
        "vocs_machina",
        "['year','month','day']",
        "parquet",
    ]

    with (
        patch("sys.argv", argv),
        patch.object(
            _job, "add_validation_target_args", side_effect=_add_validation_target_args
        ),
        patch.object(
            _job,
            "resolve_datalake_write_target",
            return_value=(
                "datalake_vocs_machina_raw",
                "vocs_machina",
                "s3://prod-bucket/prod/datalake_vocs_machina_raw/",
            ),
        ),
        patch.object(
            _job.DatalakeMetastoreService,
            "get_db_info",
            return_value={
                "db_raw_databricks": "datalake_vocs_machina_raw",
                "db_raw_path": "s3://prod-bucket/prod/datalake_vocs_machina_raw/",
            },
        ),
        patch.object(_job, "SparkClient", return_value=spark_client),
        patch.object(_job, "S3Consumer", return_value=s3_consumer),
        patch.object(_job, "S3Loader", return_value=s3_loader),
        patch.object(
            _job, "SparkMetastoreService", return_value=spark_metastore_service
        ),
        patch.object(_job, "SparkMetastoreLoader", return_value=spark_metastore_loader),
    ):
        _job.main()  # must not raise

    s3_loader.load_df.assert_not_called()
    spark_metastore_loader.update_metastore.assert_not_called()


def test_main_reads_only_finalized_part_files():
    spark_client = MagicMock()
    s3_consumer = MagicMock()
    s3_loader = MagicMock()
    spark_metastore_service = MagicMock()
    spark_metastore_loader = MagicMock()
    day_df = MagicMock()
    day_df.rdd.isEmpty.return_value = False

    source_root = (
        "s3://data-science.s3.data.quintoandar.com.br/post-contract/vocs-machina"
    )
    argv = [
        "load_vocs_machina_raw",
        "prod",
        "prod-bucket",
        "vocs_machina",
        source_root,
        "2026-06-11",
        "2026-06-11",
        "vocs_machina",
        "['year','month','day']",
        "parquet",
    ]

    with (
        patch("sys.argv", argv),
        patch.object(
            _job,
            "add_validation_target_args",
            side_effect=_add_validation_target_args,
        ),
        patch.object(
            _job,
            "resolve_datalake_write_target",
            return_value=(
                "datalake_vocs_machina_raw",
                "vocs_machina",
                "s3://prod-bucket/prod/datalake_vocs_machina_raw/",
            ),
        ),
        patch.object(
            _job.DatalakeMetastoreService,
            "get_db_info",
            return_value={
                "db_raw_databricks": "datalake_vocs_machina_raw",
                "db_raw_path": "s3://prod-bucket/prod/datalake_vocs_machina_raw/",
            },
        ),
        patch.object(_job, "SparkClient", return_value=spark_client),
        patch.object(_job, "S3Consumer", return_value=s3_consumer),
        patch.object(_job, "S3Loader", return_value=s3_loader),
        patch.object(
            _job, "SparkMetastoreService", return_value=spark_metastore_service
        ),
        patch.object(_job, "SparkMetastoreLoader", return_value=spark_metastore_loader),
        patch.object(_job, "_prepare_day_df", return_value=day_df),
        patch.object(_job, "_dedup_df", return_value=day_df),
    ):
        _job.main()

    expected_day_uri = build_day_partition_uri(source_root, "2026-06-11")
    s3_consumer.get_data_from_file.assert_called_once_with(
        expected_day_uri,
        "parquet",
        {
            "recursiveFileLookup": "true",
            "pathGlobFilter": _job.FINALIZED_PARQUET_GLOB,
        },
    )
    # Guard against a regression that would ingest partial checkpoints.
    assert _job.FINALIZED_PARQUET_GLOB == "part-*.parquet"
