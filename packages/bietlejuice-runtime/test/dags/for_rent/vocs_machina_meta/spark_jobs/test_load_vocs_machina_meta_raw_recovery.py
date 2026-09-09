"""Unit tests for VOCS-61 recovery write guards in load_vocs_machina_meta_raw."""

import json
from unittest.mock import MagicMock

import pytest

pytest.importorskip("pyspark")

from dags.for_rent.vocs_machina_meta.spark_jobs import (  # noqa: E402
    load_vocs_machina_meta_raw as job,
)

RUN_ID = "run-2026-08-23T00-00-00"


def _write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2))


def _backfill_plan_payload():
    return {
        "partitions": 4,
        "estimated_calls": 200,
        "estimated_llm_seconds": 120.5,
        "estimated_wall_clock_seconds": 300,
        "estimated_runs_needed": 2,
        "estimate_basis_counts": {
            "measured_from_last_success": 3,
            "config_default": 1,
        },
        "caution": "high_volume",
        "throughput_calibration": {
            "calls_per_second": 1.5,
            "basis": "measured",
            "config_default": 1.0,
        },
        "backfill_breaker": {
            "tripped": False,
            "fingerprint": "xyz",
            "reasons": [],
            "n_prompts": 0,
            "n_partitions": 0,
            "estimated_calls": 0,
            "approved": None,
            "refused": False,
            "approved_pairs": [],
        },
    }


@pytest.fixture
def source_root(tmp_path):
    return tmp_path / "vocs-machina"


class TestValidateRecoverySource:
    def test_zero_row_recovery_source_fails_before_write(self, spark):
        empty_df = spark.createDataFrame([], job.OUTPUT_SCHEMAS["backfill_plans"])

        with pytest.raises(RuntimeError, match="aborting before any write"):
            job._validate_recovery_source("backfill_plans", empty_df)

    def test_missing_recovery_source_fails_before_write(self):
        with pytest.raises(RuntimeError, match="aborting before any write"):
            job._validate_recovery_source("backfill_plans", None)

    def test_non_recovery_empty_source_is_allowed(self, spark):
        empty_df = spark.createDataFrame([], job.OUTPUT_SCHEMAS["run_summaries"])

        job._validate_recovery_source("run_summaries", empty_df)

    def test_recovery_with_valid_payload_passes(self, spark, source_root):
        _write_json(
            source_root / "_meta" / "backfill_plans" / f"{RUN_ID}.json",
            _backfill_plan_payload(),
        )
        parsed = job.build_backfill_plans_df(spark, str(source_root))

        job._validate_recovery_source("backfill_plans", parsed)

    def test_all_null_payload_rows_rejected_before_write(self, spark):
        garbage_df = spark.createDataFrame(
            [(RUN_ID, None, None)],
            "run_id string, partitions int, estimated_calls int",
        )

        with pytest.raises(RuntimeError, match="valid_payload_row_count=0"):
            job._validate_recovery_source("backfill_plans", garbage_df)


class TestRequireStaticPartitionOverwriteMode:
    def test_missing_config_fails_before_overwrite(self, spark):
        spark.conf.unset(job.PARTITION_OVERWRITE_MODE_KEY)

        with pytest.raises(RuntimeError, match="is unset"):
            job._require_static_partition_overwrite_mode(spark)

    def test_non_static_mode_fails_before_overwrite(self, spark):
        spark.conf.set(job.PARTITION_OVERWRITE_MODE_KEY, "dynamic")

        with pytest.raises(RuntimeError, match="requires 'static'"):
            job._require_static_partition_overwrite_mode(spark)

    def test_explicit_static_mode_passes(self, spark):
        spark.conf.set(job.PARTITION_OVERWRITE_MODE_KEY, "static")

        job._require_static_partition_overwrite_mode(spark)

    def test_static_mode_is_case_insensitive(self, spark):
        spark.conf.set(job.PARTITION_OVERWRITE_MODE_KEY, "STATIC")

        job._require_static_partition_overwrite_mode(spark)

    def test_bootstrap_static_passes_when_session_explicitly_static(self, spark):
        spark.sparkContext.getConf().set(job.PARTITION_OVERWRITE_MODE_KEY, "static")
        spark.conf.set(job.PARTITION_OVERWRITE_MODE_KEY, "static")

        job._require_static_partition_overwrite_mode(spark)

    def test_session_dynamic_overrides_bootstrap_static(self, spark):
        spark.sparkContext.getConf().set(job.PARTITION_OVERWRITE_MODE_KEY, "static")
        spark.conf.set(job.PARTITION_OVERWRITE_MODE_KEY, "dynamic")

        with pytest.raises(RuntimeError, match="requires 'static'"):
            job._require_static_partition_overwrite_mode(spark)


class TestResolveRawWriteOptions:
    def test_recovery_table_uses_full_overwrite(self):
        merge_on, when_matched = job.resolve_raw_write_options("backfill_plans")

        assert merge_on is None
        assert when_matched is None

    def test_other_tables_use_insert_only_merge(self):
        merge_on, when_matched = job.resolve_raw_write_options("run_summaries")

        assert merge_on == ["run_id"]
        assert when_matched == job.WHEN_MATCHED_UPDATE_CONDITION


class TestWriteRawTable:
    def test_recovery_write_checks_static_mode_before_loader(self, spark):
        spark.conf.set(job.PARTITION_OVERWRITE_MODE_KEY, "dynamic")
        loader = MagicMock()
        source_df = spark.createDataFrame(
            [("run-a", 1, 2)],
            "run_id string, partitions int, estimated_calls int",
        )

        with pytest.raises(RuntimeError, match="requires 'static'"):
            job.write_raw_table(
                spark,
                loader,
                "backfill_plans",
                "db.backfill_plans",
                "s3://bucket/backfill_plans",
                source_df,
                ["year", "month", "day"],
            )

        loader.load_table.assert_not_called()

    def test_session_dynamic_overrides_bootstrap_static_before_loader(self, spark):
        spark.sparkContext.getConf().set(job.PARTITION_OVERWRITE_MODE_KEY, "static")
        spark.conf.set(job.PARTITION_OVERWRITE_MODE_KEY, "dynamic")
        loader = MagicMock()
        source_df = spark.createDataFrame(
            [("run-a", 1, 2)],
            "run_id string, partitions int, estimated_calls int",
        )

        with pytest.raises(RuntimeError, match="requires 'static'"):
            job.write_raw_table(
                spark,
                loader,
                "backfill_plans",
                "db.backfill_plans",
                "s3://bucket/backfill_plans",
                source_df,
                ["year", "month", "day"],
            )

        loader.load_table.assert_not_called()

    def test_recovery_write_calls_loader_with_overwrite_options(self, spark):
        spark.conf.set(job.PARTITION_OVERWRITE_MODE_KEY, "static")
        loader = MagicMock()
        source_df = spark.createDataFrame(
            [("run-a", 1, 2)],
            "run_id string, partitions int, estimated_calls int",
        )

        job.write_raw_table(
            spark,
            loader,
            "backfill_plans",
            "db.backfill_plans",
            "s3://bucket/backfill_plans",
            source_df,
            ["year", "month", "day"],
        )

        loader.load_table.assert_called_once_with(
            table_name="db.backfill_plans",
            path="s3://bucket/backfill_plans",
            source_df=source_df,
            partition_by=["year", "month", "day"],
            merge_on=None,
            when_matched_update_condition=None,
        )

    def test_non_recovery_table_uses_insert_only_merge(self, spark):
        loader = MagicMock()
        source_df = spark.createDataFrame([("run-a",)], "run_id string")

        job.write_raw_table(
            spark,
            loader,
            "run_summaries",
            "db.run_summaries",
            "s3://bucket/run_summaries",
            source_df,
            ["year", "month", "day"],
        )

        loader.load_table.assert_called_once_with(
            table_name="db.run_summaries",
            path="s3://bucket/run_summaries",
            source_df=source_df,
            partition_by=["year", "month", "day"],
            merge_on=["run_id"],
            when_matched_update_condition=job.WHEN_MATCHED_UPDATE_CONDITION,
        )
