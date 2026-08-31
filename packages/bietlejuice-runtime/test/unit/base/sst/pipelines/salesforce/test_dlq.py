"""Unit tests for the Salesforce CDC dead-letter (DLQ) pipeline."""

from types import SimpleNamespace
from unittest import mock

import pytest

from bietlejuice.base.sst.pipelines.salesforce import dlq as pipeline

TARGET_TABLE = "events_case"
API_ENTITY = "Case"
PARTITION_DATE = "2026-08-21"
PARTITION_HOUR = "10"
ENDPOINT = "https://example.my.salesforce.com"
BUCKET = "test-datalake-bucket"
UPDATED_IDS = ["001AAA", "001BBB"]
UNIQUE_GRAIN = [
    "id_record",
    "transaction_key",
    "sequence_number",
    "commit_number",
]
SCHEMA_DEFINITION = {
    "fields": [
        {"name": "Id", "type": "id"},
        {"name": "LastModifiedDate", "type": "datetime"},
        {"name": "Status", "type": "string"},
        {"name": "Unused", "type": "string"},
    ],
}


def _args():
    return [
        "--job_name",
        "salesforce_cdc",
        "--env",
        "forno",
        "--target_table",
        TARGET_TABLE,
        "--dag_name",
        "salesforce_cdc",
        "--partition_date",
        PARTITION_DATE,
        "--partition_hour",
        PARTITION_HOUR,
        "--api_entity",
        API_ENTITY,
        "--salesforce_endpoint",
        ENDPOINT,
        "--bucket",
        BUCKET,
    ]


def _chained_df(name="df"):
    df = mock.MagicMock(name=name)
    df.columns = ["id_record", "LastModifiedDate", "Status"]
    df.withColumn.return_value = df
    df.drop.return_value = df
    df.dropDuplicates.return_value = df
    df.select.return_value = df
    df.where.return_value = df
    df.join.return_value = df
    df.distinct.return_value = df
    return df


@pytest.fixture
def patched():
    with (
        mock.patch.object(pipeline, "F"),
        mock.patch.object(pipeline, "standard_now", return_value="2026-08-24 10:00:00"),
        mock.patch.object(pipeline, "retrieve_spark_session") as retrieve,
        mock.patch.object(pipeline, "retrieve_token", return_value="token"),
        mock.patch.object(
            pipeline,
            "build_salesforce_table_description_header",
            return_value={"Authorization": "Bearer token"},
        ),
        mock.patch.object(pipeline, "get_request", return_value=SCHEMA_DEFINITION),
        mock.patch.object(
            pipeline, "retrieve_missing_events", return_value=UPDATED_IDS
        ) as missing,
        mock.patch.object(
            pipeline, "build_query_chunks", return_value=(["SELECT Id FROM Case"], [])
        ) as chunks,
        mock.patch.object(pipeline, "retrieve_salesforce_event") as retrieve_event,
        mock.patch.object(pipeline, "apply_schema_remaps") as remap,
        mock.patch.object(pipeline, "validate_and_upsert") as upsert,
        mock.patch.object(pipeline, "reprocess_cdc_events") as reprocess,
        mock.patch.object(pipeline, "save_dlq_volume_metrics") as save_metric,
    ):
        spark = mock.MagicMock(name="spark")
        spark.read.table.return_value = _chained_df("raw_table")
        retrieve.return_value = spark
        remapped = _chained_df("remapped")
        reprocessed = _chained_df("reprocessed")
        remap.return_value = remapped
        retrieve_event.return_value = _chained_df("recovered")
        reprocess.return_value = reprocessed
        yield SimpleNamespace(
            spark=spark,
            missing=missing,
            chunks=chunks,
            retrieve_event=retrieve_event,
            upsert=upsert,
            reprocess=reprocess,
            remapped=remapped,
            reprocessed=reprocessed,
            save_metric=save_metric,
        )


def _assert_metric_recorded(save_metric, raw_df=None, clean_df=None):
    """The metric is always recorded once, with the partition it processed."""
    save_metric.assert_called_once()
    kwargs = save_metric.call_args.kwargs
    assert kwargs["bucket"] == BUCKET
    assert kwargs["target_table"] == TARGET_TABLE
    assert kwargs["env"] == "forno"
    assert kwargs["partition_date"] == PARTITION_DATE
    assert kwargs["partition_hour"] == PARTITION_HOUR
    assert kwargs["raw_df"] is raw_df
    assert kwargs["clean_df"] is clean_df


class TestDlqPipeline:
    def test_exits_when_no_missing_events(self, patched):
        patched.missing.return_value = []

        pipeline.dlq_pipeline(args=_args())

        patched.missing.assert_called_once_with(
            spark=patched.spark,
            target_table=TARGET_TABLE,
            partition_date=PARTITION_DATE,
            partition_hour=PARTITION_HOUR,
            raw_schema="datalake_salesforce_raw",
            clean_schema="datalake_salesforce_clean",
        )
        patched.retrieve_event.assert_not_called()
        patched.upsert.assert_not_called()
        patched.reprocess.assert_not_called()
        _assert_metric_recorded(patched.save_metric)

    def test_upserts_raw_and_reprocesses_clean(self, patched):
        pipeline.dlq_pipeline(args=_args())

        raw_table = f"datalake_salesforce_raw.{TARGET_TABLE}"
        _, event_kwargs = patched.retrieve_event.call_args
        assert event_kwargs["event_type"] == pipeline.RECOVERY_EVENT_TYPE
        assert event_kwargs["api_entity"] == API_ENTITY

        _, upsert_kwargs = patched.upsert.call_args
        assert upsert_kwargs["target_table"] == raw_table
        assert upsert_kwargs["source_df"] is patched.remapped
        assert upsert_kwargs["match_fields"] == UNIQUE_GRAIN

        _, chunk_kwargs = patched.chunks.call_args
        assert chunk_kwargs["id_lst"] == UPDATED_IDS
        assert "Id" in chunk_kwargs["columns_name"]
        assert "LastModifiedDate" in chunk_kwargs["columns_name"]
        assert "Status" in chunk_kwargs["columns_name"]
        assert "Unused" not in chunk_kwargs["columns_name"]

        patched.reprocess.assert_called_once_with(
            spark=patched.spark,
            table=TARGET_TABLE,
            id_list=UPDATED_IDS,
        )
        _assert_metric_recorded(
            patched.save_metric,
            raw_df=patched.remapped,
            clean_df=patched.reprocessed,
        )

    def test_exits_when_query_chunks_are_empty(self, patched):
        patched.chunks.return_value = ([], [])

        pipeline.dlq_pipeline(args=_args())

        patched.retrieve_event.assert_not_called()
        patched.upsert.assert_not_called()
        patched.reprocess.assert_not_called()
        _assert_metric_recorded(patched.save_metric)

    def test_main_entrypoint_parses_cli_argv(self, patched):
        with mock.patch("sys.argv", ["dlq.py", *_args()]):
            pipeline.dlq_pipeline()

        patched.reprocess.assert_called_once_with(
            spark=patched.spark,
            table=TARGET_TABLE,
            id_list=UPDATED_IDS,
        )


class TestReprocessCdcEvents:
    def test_returns_early_when_id_list_is_empty(self):
        spark = mock.MagicMock()

        result = pipeline.reprocess_cdc_events(spark, TARGET_TABLE, [])

        assert result is None
        spark.read.table.assert_not_called()

    def test_upserts_clean_for_ids_with_create_or_recovery(self):
        spark = mock.MagicMock()
        event_df = _chained_df("event_df")
        spark.read.table.return_value = event_df
        spark.createDataFrame.return_value = mock.MagicMock(name="ids_df")
        normalized = _chained_df("normalized")
        cdc = _chained_df("cdc")
        updated = _chained_df("updated")
        cdc.dropDuplicates.return_value = updated
        updated.withColumn.return_value = updated

        with (
            mock.patch.object(pipeline, "F"),
            mock.patch.object(
                pipeline, "standard_now", return_value="2026-08-24 10:00:00"
            ),
            mock.patch.object(
                pipeline, "normalize_df_columns", return_value=normalized
            ),
            mock.patch.object(pipeline, "in_memory_cdc_udpate", return_value=cdc),
            mock.patch.object(pipeline, "validate_and_upsert") as upsert,
        ):
            result = pipeline.reprocess_cdc_events(spark, TARGET_TABLE, UPDATED_IDS)

        spark.read.table.assert_called_once_with(
            f"datalake_salesforce_raw.{TARGET_TABLE}"
        )
        assert result is updated
        upsert.assert_called_once()
        _, kwargs = upsert.call_args
        assert kwargs["target_table"] == f"datalake_salesforce_clean.{TARGET_TABLE}"
        assert kwargs["match_fields"] == UNIQUE_GRAIN
        assert kwargs["source_df"] is updated
