"""Unit tests for the SFMC file-based raw pipeline orchestration."""

from types import SimpleNamespace
from unittest import mock

import pytest

from bietlejuice.base.sst.pipelines.sfmc import raw_v2 as pipeline

BUCKET = "test-bucket"
TARGET_SCHEMA = "datalake_sfmc_raw"
PARTITION_DATE = "2026-08-05"
TEAM_NAME = "growth"
SOURCE_PREFIX = "raw/sfmc/tracking-data"
SOURCE_ROOT = f"s3a://{BUCKET}/{SOURCE_PREFIX}"


def _args(de_types="send,return,template", table_prefix=None, csv_delimiter=None):
    """CLI args the @default_args wrapper parses into the cfg namespace."""
    args = [
        "--job_name",
        "load_sfmc_tracking_raw",
        "--env",
        "forno",
        "--target_schema",
        TARGET_SCHEMA,
        "--target_table",
        "unused",
        "--dag_name",
        "salesforce_marketing_cloud",
        "--bucket",
        BUCKET,
        "--partition_date",
        PARTITION_DATE,
        "--team_name",
        TEAM_NAME,
        "--de_types",
        de_types,
        "--source_prefix",
        SOURCE_PREFIX,
    ]
    if table_prefix is not None:
        args += ["--table_prefix", table_prefix]
    if csv_delimiter is not None:
        args += ["--csv_delimiter", csv_delimiter]
    return args


def _csv_path(de_type):
    return f"{SOURCE_ROOT}/{de_type}_{TEAM_NAME}_{PARTITION_DATE}.csv"


@pytest.fixture
def patched():
    """Patch every collaborator that touches Spark; leave control flow real."""
    with (
        mock.patch.object(pipeline, "F") as mock_f,
        mock.patch.object(pipeline, "retrieve_spark_session") as retrieve,
        mock.patch.object(pipeline, "read_csv_if_exists") as read,
        mock.patch.object(pipeline, "validate_and_write") as write,
        mock.patch.object(pipeline, "save_volume_metric") as metric,
    ):
        spark = mock.MagicMock(name="spark")
        retrieve.return_value = spark
        mock_f.lit.return_value = mock.MagicMock(name="lit_expression")
        mock_f.current_timestamp.return_value = mock.MagicMock(name="current_timestamp")
        mock_f.date_format.return_value = mock.MagicMock(name="ts_load_expression")
        mock_f.input_file_name.return_value = mock.MagicMock(name="input_file_name")
        # withColumn returns the same mock, so the stamped frame handed to the
        # writer is identity-comparable with the frame the reader returned.
        raw_df = mock.MagicMock(name="raw_df")
        raw_df.withColumn.return_value = raw_df
        read.return_value = raw_df
        yield SimpleNamespace(
            spark=spark,
            read=read,
            write=write,
            metric=metric,
            raw_df=raw_df,
            f=mock_f,
        )


class TestSfmcRawV2Pipeline:
    def test_builds_the_exact_path_per_delivery_type(self, patched):
        pipeline.sfmc_raw_v2_pipeline(args=_args(de_types="send,return"))

        called_paths = [call.kwargs["csv_path"] for call in patched.read.call_args_list]
        assert called_paths == [_csv_path("send"), _csv_path("return")]

    def test_writes_one_table_per_delivery_type(self, patched):
        pipeline.sfmc_raw_v2_pipeline(args=_args(de_types="send,return"))

        assert patched.write.call_count == 2
        written_tables = [
            call.kwargs["target_table"] for call in patched.write.call_args_list
        ]
        assert written_tables == [f"{TARGET_SCHEMA}.send", f"{TARGET_SCHEMA}.return"]

        assert patched.write.call_args_list[0].kwargs == dict(
            spark=patched.spark,
            df=patched.raw_df,
            target_table=f"{TARGET_SCHEMA}.send",
            partition_filter=f"partition_date = '{PARTITION_DATE}'",
            partition_cols=["partition_date"],
            overwrite_schema=True,
            table_location=f"s3a://{BUCKET}/raw/{TARGET_SCHEMA}/send",
        )

    def test_skips_a_delivery_type_that_was_not_delivered(self, patched):
        patched.read.side_effect = [patched.read.return_value, None]

        pipeline.sfmc_raw_v2_pipeline(args=_args(de_types="send,return"))

        patched.write.assert_called_once()
        assert patched.write.call_args.kwargs["target_table"] == f"{TARGET_SCHEMA}.send"

    def test_is_a_no_op_when_nothing_was_delivered(self, patched):
        patched.read.return_value = None

        pipeline.sfmc_raw_v2_pipeline(args=_args(de_types="send,return"))

        patched.write.assert_not_called()
        patched.metric.assert_not_called()

    def test_saves_a_volume_metric_per_written_table(self, patched):
        pipeline.sfmc_raw_v2_pipeline(args=_args(de_types="send"))

        patched.metric.assert_called_once_with(
            spark=patched.spark,
            df=patched.raw_df,
            grain=["partition_date"],
            metric_name="sfmc_raw_volume",
            table_name=f"{TARGET_SCHEMA}.send",
            env="forno",
            layer="raw",
            partition_cols=["partition_date"],
            table_location=f"s3a://{BUCKET}/sst_metrics/sfmc_raw_volume",
        )

    def test_stamps_only_the_lineage_columns(self, patched):
        # Delivered column names are kept verbatim: raw adds lineage and
        # nothing else, so any renaming is the clean layer's business.
        pipeline.sfmc_raw_v2_pipeline(args=_args(de_types="send"))

        stamped_columns = [
            call.args[0] for call in patched.raw_df.withColumn.call_args_list
        ]
        assert stamped_columns == ["source_file", "ts_load", "partition_date"]
        assert patched.write.call_args.kwargs["df"] is patched.raw_df

    def test_source_file_uses_the_spark_input_file_name(self, patched):
        # source_file is read straight from Spark's own file metadata rather
        # than re-derived from the driver-side csv_path string, so it stays
        # correct even if a future reader ever spans more than one file.
        pipeline.sfmc_raw_v2_pipeline(args=_args(de_types="send"))

        source_file_call = patched.raw_df.withColumn.call_args_list[0]
        assert source_file_call.args == ("source_file", patched.f.input_file_name())

    def test_applies_table_prefix_and_csv_delimiter(self, patched):
        pipeline.sfmc_raw_v2_pipeline(
            args=_args(de_types="send", table_prefix="tracking_", csv_delimiter="\t")
        )

        assert (
            patched.write.call_args.kwargs["target_table"]
            == f"{TARGET_SCHEMA}.tracking_send"
        )
        assert (
            patched.write.call_args.kwargs["table_location"]
            == f"s3a://{BUCKET}/raw/{TARGET_SCHEMA}/tracking_send"
        )
        assert patched.read.call_args.kwargs["delimiter"] == "\t"

    def test_dedupes_a_repeated_de_type(self, patched):
        pipeline.sfmc_raw_v2_pipeline(args=_args(de_types="send,send"))

        assert patched.read.call_count == 1
        assert patched.write.call_count == 1

    def test_rejects_an_empty_de_types_argument(self, patched):
        with pytest.raises(ValueError, match="de_types"):
            pipeline.sfmc_raw_v2_pipeline(args=_args(de_types=" , "))

        patched.read.assert_not_called()

    def test_loads_healthy_types_and_then_fails_the_job(self, patched):
        patched.write.side_effect = [RuntimeError("delta type mismatch"), None]

        with pytest.raises(RuntimeError, match="1 of 2 delivery types failed"):
            pipeline.sfmc_raw_v2_pipeline(args=_args(de_types="send,return"))

        assert patched.write.call_count == 2
        assert (
            patched.write.call_args_list[1].kwargs["target_table"]
            == f"{TARGET_SCHEMA}.return"
        )

    def test_a_failing_metric_emission_still_fails_the_job(self, patched):
        # A successful write followed by a metric failure is treated as a
        # failed delivery type too: retrying re-runs the (idempotent) write
        # and gets the metric recorded, rather than silently losing that
        # day's volume data.
        patched.metric.side_effect = RuntimeError("metrics table unreachable")

        with pytest.raises(RuntimeError, match="1 of 1 delivery types failed"):
            pipeline.sfmc_raw_v2_pipeline(args=_args(de_types="send"))

        patched.write.assert_called_once()
