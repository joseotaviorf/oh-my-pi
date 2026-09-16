"""Unit tests for the Salesforce API_v2 clean-layer pipeline orchestration."""

from types import SimpleNamespace
from unittest import mock

import pytest

from bietlejuice.base.sst.pipelines.salesforce import api_v2_clean as pipeline

SOURCE_SCHEMA = "datalake_salesforce_raw"
TARGET_SCHEMA = "datalake_salesforce_clean"
TARGET_TABLE = "task_v2"
PARTITION_DATE = "2026-06-02"
BUCKET = "test-bucket"
TARGET = f"{TARGET_SCHEMA}.{TARGET_TABLE}"


def _args(sync_hive="True", partition_hour=None):
    """CLI args the @default_args wrapper parses into the cfg namespace."""
    argv = [
        "--job_name",
        "salesforce_api",
        "--env",
        "forno",
        "--target_schema",
        TARGET_SCHEMA,
        "--target_table",
        TARGET_TABLE,
        "--source_schema",
        SOURCE_SCHEMA,
        "--partition_date",
        PARTITION_DATE,
        "--bucket",
        BUCKET,
        "--sync_hive",
        sync_hive,
        "--dag_name",
        "salesforce_api",
    ]
    if partition_hour is not None:
        argv += ["--partition_hour", partition_hour]
    return argv


@pytest.fixture
def patched():
    """Patch every collaborator that touches Spark / IO; leave control flow real."""
    with (
        mock.patch.object(pipeline, "F"),
        mock.patch.object(pipeline, "standard_now", return_value="2026-06-02 03:00:00"),
        mock.patch.object(pipeline, "retrieve_spark_session") as retrieve,
        mock.patch.object(pipeline, "conform_api_clean"),
        mock.patch.object(pipeline, "build_api_versioned_df") as build,
        mock.patch.object(pipeline, "basic_quality_checks"),
        mock.patch.object(pipeline, "partition_has_data") as has_data,
        mock.patch.object(pipeline, "_table_exists") as table_exists,
        mock.patch.object(pipeline, "validate_and_write") as v_write,
        mock.patch.object(pipeline, "validate_and_upsert") as v_upsert,
        mock.patch.object(pipeline, "save_volume_metric") as metric,
    ):
        spark = mock.MagicMock(name="spark")
        retrieve.return_value = spark
        out_df = mock.MagicMock(name="out_df")
        out_df.columns = ["partition_date"]
        build.return_value.withColumn.return_value = out_df
        yield SimpleNamespace(
            spark=spark,
            has_data=has_data,
            table_exists=table_exists,
            validate_and_write=v_write,
            validate_and_upsert=v_upsert,
            metric=metric,
            out_df=out_df,
        )


class TestSalesforceApiCleanPipeline:
    def test_exits_when_no_raw_data(self, patched):
        patched.has_data.return_value = False  # source empty

        pipeline.salesforce_api_clean_pipeline(args=_args())

        source = f"{SOURCE_SCHEMA}.{TARGET_TABLE}"
        patched.has_data.assert_called_once_with(
            patched.spark, source, PARTITION_DATE, None
        )
        patched.validate_and_write.assert_not_called()
        patched.validate_and_upsert.assert_not_called()
        patched.metric.assert_not_called()

    def test_bootstrap_calls_validate_and_write_with_sync_flags(self, patched):
        patched.has_data.return_value = True  # source has data
        patched.table_exists.return_value = False

        pipeline.salesforce_api_clean_pipeline(args=_args(sync_hive="True"))

        patched.validate_and_upsert.assert_not_called()
        patched.validate_and_write.assert_called_once()
        _, kwargs = patched.validate_and_write.call_args
        assert kwargs["target_table"] == TARGET
        assert kwargs["partition_cols"] == ["_is_current"]
        assert kwargs["sync_hive"] is True
        assert kwargs["sync_secondary_catalog"] is True

    def test_incremental_calls_upsert_on_existing_target(self, patched):
        patched.has_data.return_value = True
        patched.table_exists.return_value = True

        pipeline.salesforce_api_clean_pipeline(args=_args())

        patched.validate_and_write.assert_not_called()
        patched.validate_and_upsert.assert_called_once()
        _, kwargs = patched.validate_and_upsert.call_args
        assert kwargs["target_table"] == TARGET
        assert kwargs["match_fields"] == ["id_record", "_effective_timestamp"]

    def test_saves_volume_metric(self, patched):
        patched.has_data.return_value = True
        patched.table_exists.return_value = True

        pipeline.salesforce_api_clean_pipeline(args=_args())

        patched.metric.assert_called_once()
        _, kwargs = patched.metric.call_args
        assert kwargs["grain"] == ["partition_date"]
        assert kwargs["layer"] == "clean"
        assert kwargs["metric_name"] == "api_clean_volume"
        assert kwargs["table_name"] == TARGET

    def test_hourly_run_narrows_sensor_and_source_read(self, patched):
        patched.has_data.return_value = True
        patched.table_exists.return_value = True

        pipeline.salesforce_api_clean_pipeline(args=_args(partition_hour="00"))

        source = f"{SOURCE_SCHEMA}.{TARGET_TABLE}"
        # "00" must be treated as a real hour, not a falsy value.
        patched.has_data.assert_called_once_with(
            patched.spark, source, PARTITION_DATE, "00"
        )
        date_filtered = patched.spark.read.table.return_value.where.return_value
        date_filtered.where.assert_called_once()

    def test_daily_run_does_not_add_hour_read_filter(self, patched):
        patched.has_data.return_value = True
        patched.table_exists.return_value = True

        pipeline.salesforce_api_clean_pipeline(args=_args())

        date_filtered = patched.spark.read.table.return_value.where.return_value
        date_filtered.where.assert_not_called()

    def test_hourly_metric_grain_includes_hour_when_column_present(self, patched):
        patched.has_data.return_value = True
        patched.table_exists.return_value = True
        patched.out_df.columns = ["partition_date", "partition_hour"]

        pipeline.salesforce_api_clean_pipeline(args=_args(partition_hour="13"))

        _, kwargs = patched.metric.call_args
        assert kwargs["grain"] == ["partition_date", "partition_hour"]
        assert kwargs["partition_cols"] == ["partition_date"]

    def test_hourly_metric_grain_falls_back_when_column_absent(self, patched):
        """Incremental runs align to the target schema; until the clean table
        carries partition_hour the metric stays at daily grain."""
        patched.has_data.return_value = True
        patched.table_exists.return_value = True
        patched.out_df.columns = ["partition_date"]

        pipeline.salesforce_api_clean_pipeline(args=_args(partition_hour="13"))

        _, kwargs = patched.metric.call_args
        assert kwargs["grain"] == ["partition_date"]
