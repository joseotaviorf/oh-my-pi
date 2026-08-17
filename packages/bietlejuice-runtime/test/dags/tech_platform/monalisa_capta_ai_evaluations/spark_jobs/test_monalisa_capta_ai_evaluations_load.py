"""main() tests for the Unity Catalog secondary sync on Capta AI evaluations.

Run::

    uv run --directory packages/bietlejuice-runtime pytest \\
        test/dags/tech_platform/monalisa_capta_ai_evaluations/spark_jobs/test_monalisa_capta_ai_evaluations_load.py -q
"""

from argparse import Namespace
from datetime import datetime
from unittest.mock import MagicMock

import pytest

pytest.importorskip("pyspark")

from dags.tech_platform.monalisa_capta_ai_evaluations.spark_jobs import (  # noqa: E402
    monalisa_capta_ai_evaluations_load as load_job,
)

_TABLE = "monalisa_capta_ai_evaluations"
_LAYER_DB = "datalake_tech_platform_clean"
_LAYER_LOCATION = "s3://5a-datalake-prod/clean/tech_platform"
_DEFAULT_WRITE_PATH = f"s3://5a-datalake-prod/clean/tech_platform/{_TABLE}/"


def _args(**overrides):
    args = Namespace(
        env="prod",
        datalake_bucket="5a-datalake-prod",
        schema="tech_platform",
        load_start_date=datetime(2026, 7, 16),
        load_end_date=datetime(2026, 7, 16),
        table_name=_TABLE,
        partition_cols=["year", "month", "day"],
        target_database_name=None,
        target_table_name=None,
        path="s3://monalisa-prod/evaluations/CaptaAi/{}/{}/{}/*.ndjson.gz",
    )
    for key, value in overrides.items():
        setattr(args, key, value)
    return args


def _stub_pipeline(monkeypatch, *, records_count, clean_data_frame):
    raw_df = MagicMock(name="raw_df")
    raw_df.count.return_value = records_count
    day_frame = MagicMock(name="day_frame")

    monkeypatch.setattr(load_job, "load_data_frame", lambda path: raw_df)
    monkeypatch.setattr(load_job, "clean_df", lambda df, partition_date: day_frame)
    monkeypatch.setattr(
        load_job, "_keep_latest_per_conversation", lambda df: clean_data_frame
    )
    load_job.DatalakeMetastoreService.get_layer_info.return_value = (
        _LAYER_DB,
        _LAYER_LOCATION,
        None,
    )


class TestMainSecondaryCatalogSync:
    def test_syncs_after_delta_write_on_default_path(self, monkeypatch):
        # arrange
        args = _args()
        clean_data_frame = MagicMock(name="clean_data_frame")
        monkeypatch.setattr(load_job, "parse_arguments", lambda: args)
        _stub_pipeline(monkeypatch, records_count=4, clean_data_frame=clean_data_frame)

        loader = MagicMock()
        monkeypatch.setattr(load_job, "DeltaLoader", MagicMock(return_value=loader))
        mock_sync = MagicMock()
        mock_partitions = MagicMock(return_value=["year", "month", "day"])
        monkeypatch.setattr(
            load_job, "sync_delta_write_to_secondary_catalog", mock_sync
        )
        monkeypatch.setattr(load_job, "partition_columns_present", mock_partitions)

        call_order = []
        loader.load_table.side_effect = lambda **kwargs: call_order.append("load")
        mock_sync.side_effect = lambda *a, **k: call_order.append("sync")

        # act
        load_job.main()

        # assert
        loader.load_table.assert_called_once_with(
            table_name=f"{_LAYER_DB}.{_TABLE}",
            path=_DEFAULT_WRITE_PATH,
            source_df=clean_data_frame,
            partition_by=args.partition_cols,
            merge_on=load_job._MERGE_ON,
        )
        mock_partitions.assert_called_once_with(clean_data_frame, args.partition_cols)
        mock_sync.assert_called_once_with(
            load_job.spark,
            f"{_LAYER_DB}.{_TABLE}",
            _DEFAULT_WRITE_PATH,
            clean_data_frame,
            ["year", "month", "day"],
        )
        assert call_order == ["load", "sync"]

    def test_syncs_after_delta_write_on_validation_target(self, monkeypatch):
        # arrange
        args = _args(
            target_database_name="cluster_validation",
            target_table_name="datalake_tech_platform_clean___monalisa_capta_ai_evaluations",
        )
        clean_data_frame = MagicMock(name="clean_data_frame")
        monkeypatch.setattr(load_job, "parse_arguments", lambda: args)
        _stub_pipeline(monkeypatch, records_count=1, clean_data_frame=clean_data_frame)

        write_location = "s3://5a-datalake-forno/cluster_validation/"
        expected_path = f"{write_location.rstrip('/')}/{args.target_table_name}"
        mock_resolve = MagicMock(
            return_value=(
                args.target_database_name,
                args.target_table_name,
                write_location,
            )
        )
        monkeypatch.setattr(load_job, "resolve_datalake_write_target", mock_resolve)

        loader = MagicMock()
        monkeypatch.setattr(load_job, "DeltaLoader", MagicMock(return_value=loader))
        mock_sync = MagicMock()
        mock_partitions = MagicMock(return_value=["year", "day"])
        monkeypatch.setattr(
            load_job, "sync_delta_write_to_secondary_catalog", mock_sync
        )
        monkeypatch.setattr(load_job, "partition_columns_present", mock_partitions)

        # act
        load_job.main()

        # assert
        mock_resolve.assert_called_once_with(
            prod_database=_LAYER_DB,
            prod_table=_TABLE,
            prod_location=_LAYER_LOCATION,
            bucket=args.datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
        loader.load_table.assert_called_once_with(
            table_name=f"{args.target_database_name}.{args.target_table_name}",
            path=expected_path,
            source_df=clean_data_frame,
            partition_by=args.partition_cols,
            merge_on=load_job._MERGE_ON,
        )
        mock_sync.assert_called_once_with(
            load_job.spark,
            f"{args.target_database_name}.{args.target_table_name}",
            expected_path,
            clean_data_frame,
            ["year", "day"],
        )

    def test_skips_sync_when_no_records_in_range(self, monkeypatch):
        # arrange
        args = _args()
        monkeypatch.setattr(load_job, "parse_arguments", lambda: args)
        raw_df = MagicMock(name="raw_df")
        raw_df.count.return_value = 0
        monkeypatch.setattr(load_job, "load_data_frame", lambda path: raw_df)

        loader = MagicMock()
        monkeypatch.setattr(load_job, "DeltaLoader", MagicMock(return_value=loader))
        mock_sync = MagicMock()
        monkeypatch.setattr(
            load_job, "sync_delta_write_to_secondary_catalog", mock_sync
        )

        # act
        load_job.main()

        # assert
        loader.load_table.assert_not_called()
        mock_sync.assert_not_called()
