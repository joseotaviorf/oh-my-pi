"""Unit tests for the Salesforce DLQ volume metric."""

from unittest import mock

from bietlejuice.base.sst.domains.salesforce.recovery import volume

TARGET_TABLE = "events_case"
BUCKET = "test-datalake-bucket"
PARTITION_DATE = "2026-08-21"
PARTITION_HOUR = "10"


def _chained_df(name="df"):
    df = mock.MagicMock(name=name)
    df.withColumn.return_value = df
    return df


def _expected_fallback():
    return {
        "partition_date": PARTITION_DATE,
        "partition_hour": PARTITION_HOUR,
        "event_type": volume.DLQ_EVENT_TYPE,
    }


def _save(**overrides):
    kwargs = dict(
        bucket=BUCKET,
        target_table=TARGET_TABLE,
        env="prod",
        partition_date=PARTITION_DATE,
        partition_hour=PARTITION_HOUR,
    )
    kwargs.update(overrides)
    return kwargs


class TestSaveDlqVolumeMetrics:
    def test_writes_raw_then_clean_from_their_own_frames(self):
        spark = mock.MagicMock()
        raw_df, clean_df = _chained_df("raw"), _chained_df("clean")

        with mock.patch.object(volume, "save_volume_metric") as save:
            volume.save_dlq_volume_metrics(
                spark=spark, raw_df=raw_df, clean_df=clean_df, **_save()
            )

        assert [call.kwargs["layer"] for call in save.call_args_list] == [
            "raw",
            "clean",
        ]
        expected_location = f"s3a://{BUCKET}/sst_metrics/{volume.VOLUME_METRIC_NAME}"
        for call in save.call_args_list:
            assert call.kwargs["metric_name"] == volume.VOLUME_METRIC_NAME
            assert call.kwargs["grain"] == volume.VOLUME_METRIC_GRAIN
            assert call.kwargs["table_name"] == TARGET_TABLE
            assert call.kwargs["env"] == "prod"
            assert call.kwargs["table_location"] == expected_location
            assert call.kwargs["partition_cols"] == [
                "partition_date",
                "partition_hour",
            ]
            assert call.kwargs["fallback_grain_values"] == _expected_fallback()
            assert call.kwargs["df"] is not None

        # Each layer is counted from its own frame, not the same one twice.
        raw_call, clean_call = save.call_args_list
        assert raw_call.kwargs["df"] is not clean_call.kwargs["df"]

    def test_passes_none_through_so_core_records_a_zero_row(self):
        spark = mock.MagicMock()

        with mock.patch.object(volume, "save_volume_metric") as save:
            volume.save_dlq_volume_metrics(spark=spark, **_save())

        assert save.call_count == 2
        for call in save.call_args_list:
            assert call.kwargs["df"] is None
            assert call.kwargs["fallback_grain_values"] == _expected_fallback()
        # No frame is fabricated here — that is the core helper's job.
        spark.createDataFrame.assert_not_called()

    def test_records_zero_for_one_layer_only(self):
        spark = mock.MagicMock()

        with mock.patch.object(volume, "save_volume_metric") as save:
            volume.save_dlq_volume_metrics(
                spark=spark, raw_df=_chained_df("raw"), clean_df=None, **_save()
            )

        raw_call, clean_call = save.call_args_list
        assert raw_call.kwargs["df"] is not None
        assert clean_call.kwargs["df"] is None


class TestStampDlqEventType:
    def test_stamps_partition_and_metric_only_event_type(self):
        df = _chained_df()

        result = volume.stamp_dlq_event_type(df, PARTITION_DATE, PARTITION_HOUR)

        assert result is df
        stamped = {call.args[0] for call in df.withColumn.call_args_list}
        assert stamped == {"partition_date", "partition_hour", "event_type"}
