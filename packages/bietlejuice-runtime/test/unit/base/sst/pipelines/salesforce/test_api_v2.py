"""Unit tests for the Salesforce API_v2 raw pipeline partition handling."""

from types import SimpleNamespace
from unittest import mock

import pytest

from bietlejuice.base.sst.pipelines.salesforce import api_v2 as pipeline

TARGET_SCHEMA = "datalake_salesforce_raw"
TARGET_TABLE = "case_v2"
PARTITION_DATE = "2026-06-02"
BUCKET = "test-bucket"
ENDPOINT = "https://sf.example"


def _args(partition_hour=None):
    """CLI args the @default_args wrapper parses into the cfg namespace."""
    argv = [
        "--job_name",
        "load_case_v2",
        "--env",
        "forno",
        "--target_schema",
        TARGET_SCHEMA,
        "--target_table",
        TARGET_TABLE,
        "--partition_date",
        PARTITION_DATE,
        "--bucket",
        BUCKET,
        "--api_entity",
        "Case",
        "--endpoint",
        ENDPOINT,
        "--dag_name",
        "salesforce_api_v2",
    ]
    if partition_hour is not None:
        argv += ["--partition_hour", partition_hour]
    return argv


@pytest.fixture
def patched():
    """Patch every collaborator that touches Spark / the API; keep control flow real."""
    with (
        mock.patch.object(pipeline, "F"),
        mock.patch.object(pipeline, "retrieve_spark_session") as retrieve,
        mock.patch.object(pipeline, "retrieve_token", return_value="token"),
        mock.patch.object(pipeline, "build_salesforce_table_description_header"),
        mock.patch.object(pipeline, "get_request") as get_request,
        mock.patch.object(pipeline, "get_updated_deleted_lst") as updated_deleted,
        mock.patch.object(pipeline, "get_updated_lst_system_mod") as system_mod,
        mock.patch.object(pipeline, "SF_RAW_SCHEMA_COLS", {"case": ["Id"]}),
        mock.patch.object(
            pipeline, "build_query_chunks", return_value=(["q1"], [["001"]])
        ),
        mock.patch.object(pipeline, "paralelize_queries") as paralelize,
        mock.patch.object(pipeline, "build_fetch_partition_closure"),
        mock.patch.object(pipeline, "build_salesforce_type_schema"),
        mock.patch.object(pipeline, "build_partition_filter") as build_filter,
        mock.patch.object(pipeline, "validate_and_write") as v_write,
        mock.patch.object(pipeline, "conform_and_save_api_logs") as save_logs,
    ):
        retrieve.return_value = mock.MagicMock(name="spark")
        get_request.return_value = {
            "replicateable": True,
            "fields": [{"name": "Id", "type": "id"}],
        }
        updated_deleted.return_value = ["001"]
        system_mod.return_value = ["001"]
        request_df = mock.MagicMock(name="request_df")
        paralelize.return_value = request_df
        api_result_df = request_df.select.return_value.repartition.return_value.mapInPandas.return_value.withColumn.return_value.cache.return_value
        api_result_df.where.return_value.count.return_value = 0
        yield SimpleNamespace(
            get_request=get_request,
            updated_deleted=updated_deleted,
            system_mod=system_mod,
            build_filter=build_filter,
            validate_and_write=v_write,
            save_logs=save_logs,
        )


class TestPipelineApiRawPartitioning:
    def test_daily_run_keeps_date_only_partitioning(self, patched):
        pipeline.pipeline_api_raw(args=_args())

        assert patched.updated_deleted.call_args.kwargs["partition_hour"] is None
        patched.build_filter.assert_called_once_with({"partition_date": PARTITION_DATE})
        kwargs = patched.validate_and_write.call_args.kwargs
        assert kwargs["partition_cols"] == ["partition_date"]
        assert patched.save_logs.call_args.kwargs["partition_hour"] is None

    def test_hourly_run_partitions_by_date_and_hour(self, patched):
        pipeline.pipeline_api_raw(args=_args(partition_hour="00"))

        # "00" must be treated as a real hour, not a falsy value.
        assert patched.updated_deleted.call_args.kwargs["partition_hour"] == "00"
        patched.build_filter.assert_called_once_with(
            {"partition_date": PARTITION_DATE, "partition_hour": "00"}
        )
        kwargs = patched.validate_and_write.call_args.kwargs
        assert kwargs["partition_cols"] == ["partition_date", "partition_hour"]
        assert patched.save_logs.call_args.kwargs["partition_hour"] == "00"

    def test_hour_reaches_system_mod_for_non_replicateable_objects(self, patched):
        patched.get_request.return_value = {
            "replicateable": False,
            "fields": [{"name": "Id", "type": "id"}],
        }

        pipeline.pipeline_api_raw(args=_args(partition_hour="05"))

        patched.updated_deleted.assert_not_called()
        assert patched.system_mod.call_args.kwargs["partition_hour"] == "05"
