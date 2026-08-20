"""Unit tests for the SFMC file-based clean-layer pipeline orchestration."""

from types import SimpleNamespace
from unittest import mock

import pytest

from bietlejuice.base.sst.pipelines.sfmc import clean_v2 as pipeline

SOURCE_SCHEMA = "datalake_sfmc_raw"
TARGET_SCHEMA = "datalake_sfmc_clean"
DLQ_SCHEMA = "datalake_sfmc_dlq"
TARGET_TABLE = "send"
PARTITION_DATE = "2026-08-05"
BUCKET = "test-bucket"
TARGET = f"{TARGET_SCHEMA}.{TARGET_TABLE}"
SOURCE = f"{SOURCE_SCHEMA}.{TARGET_TABLE}"
DLQ = f"{DLQ_SCHEMA}.{TARGET_TABLE}"


def _args(sync_hive="True"):
    """CLI args the @default_args wrapper parses into the cfg namespace."""
    return [
        "--job_name",
        "load_sfmc_clean_send",
        "--env",
        "forno",
        "--target_schema",
        TARGET_SCHEMA,
        "--target_table",
        TARGET_TABLE,
        "--source_schema",
        SOURCE_SCHEMA,
        "--dlq_schema",
        DLQ_SCHEMA,
        "--partition_date",
        PARTITION_DATE,
        "--bucket",
        BUCKET,
        "--sync_hive",
        sync_hive,
        "--dag_name",
        "salesforce_marketing_cloud",
    ]


@pytest.fixture
def patched():
    """Patch every collaborator that touches Spark / IO; leave control flow real."""
    with (
        mock.patch.object(pipeline, "F") as mock_f,
        mock.patch.object(pipeline, "standard_now", return_value="2026-08-06 03:00:00"),
        mock.patch.object(pipeline, "retrieve_spark_session") as retrieve,
        mock.patch.object(pipeline, "normalize_df_columns") as normalize,
        mock.patch.object(pipeline, "conform_required_columns") as conform,
        mock.patch.object(pipeline, "flag_quality_checks") as flag,
        mock.patch.object(pipeline, "split_checked_rows") as split,
        mock.patch.object(pipeline, "partition_has_data") as has_data,
        mock.patch.object(pipeline, "_table_exists") as table_exists,
        mock.patch.object(pipeline, "validate_and_write") as write,
        mock.patch.object(pipeline, "validate_partition_readability") as readback,
        mock.patch.object(pipeline, "save_volume_metric") as volume_metric,
        mock.patch.object(pipeline, "save_quality_check_metric") as quality_metric,
    ):
        spark = mock.MagicMock(name="spark")
        retrieve.return_value = spark
        mock_f.lit.return_value = mock.MagicMock(name="lit_expression")
        mock_f.col.return_value = mock.MagicMock(name="col_expression")

        flagged_df = mock.MagicMock(name="flagged_df")
        flag.return_value.cache.return_value = flagged_df

        accepted_df = mock.MagicMock(name="accepted_df")
        clean_out_df = mock.MagicMock(name="clean_out_df")
        clean_out_df.count.return_value = 5
        accepted_df.withColumn.return_value.withColumn.return_value = clean_out_df

        rejected_df = mock.MagicMock(name="rejected_df")
        dlq_out_df = mock.MagicMock(name="dlq_out_df")
        rejected_df.withColumn.return_value = dlq_out_df
        rejected_df.count.return_value = 0

        split.return_value = (accepted_df, rejected_df)
        has_data.return_value = True
        table_exists.return_value = False

        yield SimpleNamespace(
            spark=spark,
            has_data=has_data,
            conform=conform,
            normalize=normalize,
            flag=flag,
            split=split,
            table_exists=table_exists,
            write=write,
            readback=readback,
            volume_metric=volume_metric,
            quality_metric=quality_metric,
            flagged_df=flagged_df,
            accepted_df=accepted_df,
            rejected_df=rejected_df,
            clean_out_df=clean_out_df,
            dlq_out_df=dlq_out_df,
        )


def _write_call(patched, target_table):
    return next(
        call
        for call in patched.write.call_args_list
        if call.kwargs["target_table"] == target_table
    )


class TestSfmcCleanV2Pipeline:
    def test_exits_when_the_raw_partition_is_empty(self, patched):
        patched.has_data.return_value = False

        pipeline.sfmc_clean_v2_pipeline(args=_args())

        patched.has_data.assert_called_once_with(patched.spark, SOURCE, PARTITION_DATE)
        patched.write.assert_not_called()
        patched.volume_metric.assert_not_called()
        patched.quality_metric.assert_not_called()

    def test_publishes_only_the_rows_that_passed_every_check(self, patched):
        pipeline.sfmc_clean_v2_pipeline(args=_args())

        patched.conform.assert_called_once_with(patched.normalize.return_value)
        patched.flag.assert_called_once_with(patched.conform.return_value)
        assert patched.split.call_args.args == (patched.flagged_df,)

        clean_call = _write_call(patched, TARGET)
        assert clean_call.kwargs == dict(
            spark=patched.spark,
            df=patched.clean_out_df,
            target_table=TARGET,
            partition_filter=f"partition_date = '{PARTITION_DATE}'",
            partition_cols=["partition_date"],
            overwrite_schema=True,
            table_location=f"s3a://{BUCKET}/clean/{TARGET_SCHEMA}/{TARGET_TABLE}",
            sync_hive=True,
            sync_secondary_catalog=True,
        )

    def test_caches_and_releases_the_flagged_frame(self, patched):
        pipeline.sfmc_clean_v2_pipeline(args=_args())

        patched.flag.return_value.cache.assert_called_once()
        patched.flagged_df.unpersist.assert_called_once()

    def test_releases_the_cache_even_when_a_write_fails(self, patched):
        patched.write.side_effect = RuntimeError("delta type mismatch")

        with pytest.raises(RuntimeError, match="delta type mismatch"):
            pipeline.sfmc_clean_v2_pipeline(args=_args())

        patched.flagged_df.unpersist.assert_called_once()

    def test_writes_rejected_rows_to_the_dlq_table(self, patched):
        patched.rejected_df.count.return_value = 3

        pipeline.sfmc_clean_v2_pipeline(args=_args())

        dlq_call = _write_call(patched, DLQ)
        assert dlq_call.kwargs == dict(
            spark=patched.spark,
            df=patched.dlq_out_df,
            target_table=DLQ,
            partition_filter=f"partition_date = '{PARTITION_DATE}'",
            partition_cols=["partition_date"],
            overwrite_schema=True,
            table_location=f"s3a://{BUCKET}/dlq/{DLQ_SCHEMA}/{TARGET_TABLE}",
            sync_hive=True,
            sync_secondary_catalog=True,
        )

    def test_does_not_create_a_dlq_table_when_nothing_was_rejected(self, patched):
        patched.rejected_df.count.return_value = 0
        patched.table_exists.return_value = False

        pipeline.sfmc_clean_v2_pipeline(args=_args())

        written_tables = [
            call.kwargs["target_table"] for call in patched.write.call_args_list
        ]
        assert written_tables == [TARGET]

    def test_clears_the_dlq_partition_when_an_existing_day_is_reprocessed_clean(
        self, patched
    ):
        # A rerun after SFMC re-delivered a corrected file must not leave the
        # previous run's rejects behind.
        patched.rejected_df.count.return_value = 0
        patched.table_exists.return_value = True

        pipeline.sfmc_clean_v2_pipeline(args=_args())

        dlq_call = _write_call(patched, DLQ)
        assert dlq_call.kwargs["df"] is patched.dlq_out_df

    def test_reads_the_clean_partition_back_after_writing(self, patched):
        pipeline.sfmc_clean_v2_pipeline(args=_args())

        patched.readback.assert_called_once_with(
            spark=patched.spark,
            target_table=TARGET,
            partition_date=PARTITION_DATE,
        )

    def test_fails_when_the_written_partition_cannot_be_read_back(self, patched):
        patched.readback.side_effect = ValueError("delta log unreadable")

        with pytest.raises(RuntimeError, match="post-write readback failed"):
            pipeline.sfmc_clean_v2_pipeline(args=_args())

        patched.volume_metric.assert_not_called()
        patched.quality_metric.assert_not_called()

    def test_saves_the_volume_metric_for_the_published_rows(self, patched):
        pipeline.sfmc_clean_v2_pipeline(args=_args())

        patched.volume_metric.assert_called_once_with(
            spark=patched.spark,
            df=patched.clean_out_df,
            grain=["partition_date"],
            metric_name="sfmc_clean_volume",
            table_name=TARGET,
            env="forno",
            layer="clean",
            partition_cols=["partition_date"],
            table_location=f"s3a://{BUCKET}/sst_metrics/sfmc_clean_volume",
            fallback_grain_values={"partition_date": PARTITION_DATE},
        )

    def test_skips_writing_the_clean_table_when_nothing_accepted_and_it_never_existed(
        self, patched
    ):
        # Mirrors the DLQ table's own no-op guard: a table that never had an
        # accepted row never materializes an empty clean table.
        patched.clean_out_df.count.return_value = 0
        patched.table_exists.return_value = False

        pipeline.sfmc_clean_v2_pipeline(args=_args())

        written_tables = [
            call.kwargs["target_table"] for call in patched.write.call_args_list
        ]
        assert TARGET not in written_tables
        patched.readback.assert_not_called()
        patched.volume_metric.assert_not_called()

    def test_clears_the_clean_partition_when_every_row_is_rejected_but_it_exists(
        self, patched
    ):
        # A rerun after SFMC re-delivers a corrected, now fully-rejected file
        # must not leave the previous run's accepted rows behind.
        patched.clean_out_df.count.return_value = 0
        patched.table_exists.return_value = True

        pipeline.sfmc_clean_v2_pipeline(args=_args())

        clean_call = _write_call(patched, TARGET)
        assert clean_call.kwargs["df"] is patched.clean_out_df

    def test_skips_the_readback_check_when_every_row_is_rejected(self, patched):
        # Reading back a partition written empty on purpose would just
        # confirm the expected empty result, not signal a real failure.
        patched.clean_out_df.count.return_value = 0
        patched.table_exists.return_value = True

        pipeline.sfmc_clean_v2_pipeline(args=_args())

        patched.readback.assert_not_called()

    def test_still_saves_a_zero_row_volume_metric_when_every_row_is_rejected(
        self, patched
    ):
        patched.clean_out_df.count.return_value = 0
        patched.table_exists.return_value = True

        pipeline.sfmc_clean_v2_pipeline(args=_args())

        patched.volume_metric.assert_called_once_with(
            spark=patched.spark,
            df=patched.clean_out_df,
            grain=["partition_date"],
            metric_name="sfmc_clean_volume",
            table_name=TARGET,
            env="forno",
            layer="clean",
            partition_cols=["partition_date"],
            table_location=f"s3a://{BUCKET}/sst_metrics/sfmc_clean_volume",
            fallback_grain_values={"partition_date": PARTITION_DATE},
        )

    def test_saves_the_quality_check_metric_over_every_checked_row(self, patched):
        pipeline.sfmc_clean_v2_pipeline(args=_args())

        patched.quality_metric.assert_called_once_with(
            spark=patched.spark,
            flagged_df=patched.flagged_df,
            check_cols=pipeline.CHECK_COLS,
            bucket=BUCKET,
            target_table=TARGET,
            partition_date=PARTITION_DATE,
            env="forno",
            layer="clean",
            metric_name="sfmc_clean_quality_checks",
        )

    def test_forwards_the_sync_hive_flag_to_both_tables(self, patched):
        patched.rejected_df.count.return_value = 1

        pipeline.sfmc_clean_v2_pipeline(args=_args(sync_hive="False"))

        assert _write_call(patched, TARGET).kwargs["sync_hive"] is False
        assert _write_call(patched, DLQ).kwargs["sync_hive"] is False
