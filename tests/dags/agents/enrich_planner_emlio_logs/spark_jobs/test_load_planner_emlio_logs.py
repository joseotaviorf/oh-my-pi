"""
Unit tests for load_planner_emlio_logs.py — core transformation functions only.

Four functions are exercised:
  _build_payload_envelope  → correctly identifies the three JSON envelope keys  [needs Spark]
  _deduplicate             → window function keeps the earliest partition row    [needs Spark]
  _schema_mismatches       → pure Python schema comparison                       [no Spark]
  validate_before_write    → uses a mocked DataFrame (count + schema)            [no Spark]

Infrastructure functions (_save_to_enrich, main) are intentionally excluded;
they are covered by the dev-mode Databricks notebook run with real data.
"""
from datetime import datetime
from unittest.mock import MagicMock

import pytest


# ---------------------------------------------------------------------------
# _build_payload_envelope
# ---------------------------------------------------------------------------


class TestBuildPayloadEnvelope:
    """Detect payload_type, response_type, and observability_type from JSON envelopes."""

    def test_all_three_envelope_keys_detected(self, source_df):
        """Happy path: all three envelope columns are correctly identified in one pass."""
        from dags.agents.enrich_planner_emlio_logs.spark_jobs.load_planner_emlio_logs import (
            _build_payload_envelope,
        )

        row = _build_payload_envelope(source_df).collect()[0]
        assert row["payload_type"] == "planner_agent_request"
        assert row["response_type"] == "shadow_mode_response"
        assert row["observability_type"] == "shadow_mode_observability_data"

    def test_request_id_not_chosen_as_payload_type(self, spark, source_df):
        """request_id must be filtered out even when it appears before the payload key."""
        import json

        from dags.agents.enrich_planner_emlio_logs.spark_jobs.load_planner_emlio_logs import (
            _build_payload_envelope,
        )

        inputs = json.dumps(
            {"request_id": "req-abc", "planner_agent_request": {"id_house": 1}}
        )
        df = spark.createDataFrame(
            [("uuid-r", inputs, "{}", 2026, 4, 1)], source_df.schema
        )
        row = _build_payload_envelope(df).collect()[0]
        assert row["payload_type"] == "planner_agent_request"

    def test_missing_observability_key_yields_null(self, spark, source_df):
        """When outputs has no _observability_data key, observability_type is NULL."""
        import json

        from dags.agents.enrich_planner_emlio_logs.spark_jobs.load_planner_emlio_logs import (
            _build_payload_envelope,
        )

        outputs = json.dumps({"shadow_mode_response": {"agents": [1]}})
        df = spark.createDataFrame(
            [("uuid-o", "{}", outputs, 2026, 4, 1)], source_df.schema
        )
        row = _build_payload_envelope(df).collect()[0]
        assert row["observability_type"] is None


# ---------------------------------------------------------------------------
# metrics_calculate_ranking / evaluation_cache (nested vs sibling observability)
# ---------------------------------------------------------------------------


class TestEvaluationCacheExtraction:
    """Observability scalars and evaluation_cache when data is only under response.observability_data."""

    def test_nested_observability_data_populates_evaluation_cache_clean_json(self, spark, source_df):
        """Mirrors planner_ml_service_emlio notebook path: $.response_type.observability_data..."""
        import json

        from dags.agents.enrich_planner_emlio_logs.spark_jobs.load_planner_emlio_logs import (
            INPUT_SPECS,
            OUTPUT_SPECS,
            _apply_specs,
            _build_payload_envelope,
            _extract_observability_derived,
        )

        evaluation_cache = {
            "BlakerScore": {
                "scores": [0.5, 0.6],
                "strategy_class_name": "BlakerScore",
                "strategy_repr": "repr",
            }
        }
        outputs = {
            "shadow_mode_response": {
                "agents": [101, 102],
                "group": "g",
                "observability_data": {
                    "strategy_type_used": "sale_max15_maxintraday1_blaker_score",
                    "ranked_agents_count": 2,
                    "ranking_info": {"evaluation_cache": evaluation_cache},
                },
            }
        }
        inputs = json.dumps({"planner_agent_request": {"business_context": "sale", "id_house": "1"}})
        outputs_str = json.dumps(outputs)

        df = spark.createDataFrame(
            [("uuid-nested", inputs, outputs_str, 2026, 4, 1)],
            source_df.schema,
        )
        df = _build_payload_envelope(df)
        row_env = df.collect()[0]
        assert row_env["observability_type"] is None

        df = _apply_specs(df, INPUT_SPECS + OUTPUT_SPECS)
        row_out = df.select("strategy_type_used", "ranked_agents_count").collect()[0]
        assert row_out["strategy_type_used"] == "sale_max15_maxintraday1_blaker_score"
        assert row_out["ranked_agents_count"] == 2

        df = _extract_observability_derived(df)
        clean = df.select("evaluation_cache_clean_json").collect()[0][0]
        assert clean is not None
        assert "BlakerScore" in clean


# ---------------------------------------------------------------------------
# _deduplicate
# ---------------------------------------------------------------------------


class TestDeduplicate:
    """Window function keeps one row per (uuid, ts_log), preferring the earliest partition."""

    def _dup_df(self, spark):
        from pyspark.sql.types import IntegerType, StringType, StructField, StructType, TimestampType

        ts = datetime(2026, 4, 1, 10, 0, 0)
        schema = StructType(
            [
                StructField("uuid", StringType()),
                StructField("ts_log", TimestampType()),
                StructField("year", IntegerType()),
                StructField("month", IntegerType()),
                StructField("day", IntegerType()),
            ]
        )
        return spark.createDataFrame(
            [
                ("uuid-dup", ts, 2026, 4, 1),   # later partition — should be dropped
                ("uuid-dup", ts, 2026, 3, 31),  # earlier partition — should be kept
                ("uuid-ok", ts, 2026, 4, 1),    # unique row — must survive
            ],
            schema,
        )

    def test_duplicate_uuid_ts_log_reduced_to_one(self, spark):
        from dags.agents.enrich_planner_emlio_logs.spark_jobs.load_planner_emlio_logs import (
            _deduplicate,
        )

        assert _deduplicate(self._dup_df(spark)).filter("uuid = 'uuid-dup'").count() == 1

    def test_earliest_partition_is_kept(self, spark):
        from dags.agents.enrich_planner_emlio_logs.spark_jobs.load_planner_emlio_logs import (
            _deduplicate,
        )

        row = (
            _deduplicate(self._dup_df(spark)).filter("uuid = 'uuid-dup'").collect()[0]
        )
        assert (row["month"], row["day"]) == (3, 31)

    def test_unique_rows_are_not_dropped(self, spark):
        from dags.agents.enrich_planner_emlio_logs.spark_jobs.load_planner_emlio_logs import (
            _deduplicate,
        )

        assert _deduplicate(self._dup_df(spark)).filter("uuid = 'uuid-ok'").count() == 1

    def test_same_uuid_different_ts_log_both_kept(self, spark):
        """Same uuid with different ts_log values are NOT duplicates — both rows must survive.
        The dedup window is partitionBy(uuid, ts_log), so distinct ts_log means distinct grain."""
        from pyspark.sql.types import IntegerType, StringType, StructField, StructType, TimestampType
        from dags.agents.enrich_planner_emlio_logs.spark_jobs.load_planner_emlio_logs import (
            _deduplicate,
        )

        schema = StructType(
            [
                StructField("uuid", StringType()),
                StructField("ts_log", TimestampType()),
                StructField("year", IntegerType()),
                StructField("month", IntegerType()),
                StructField("day", IntegerType()),
            ]
        )
        df = spark.createDataFrame(
            [
                ("uuid-A", datetime(2026, 4, 1, 9, 0, 0), 2026, 4, 1),
                ("uuid-A", datetime(2026, 4, 1, 10, 0, 0), 2026, 4, 1),  # different ts_log
            ],
            schema,
        )
        assert _deduplicate(df).filter("uuid = 'uuid-A'").count() == 2


# ---------------------------------------------------------------------------
# _schema_mismatches — pure Python, no Spark required
# ---------------------------------------------------------------------------


class TestSchemaMismatches:
    """_schema_mismatches returns human-readable messages for schema drift."""

    def _call(self, actual_fields, expected_fields):
        from pyspark.sql.types import StructType
        from dags.agents.enrich_planner_emlio_logs.spark_jobs.load_planner_emlio_logs import (
            _schema_mismatches,
        )

        return _schema_mismatches(StructType(actual_fields), StructType(expected_fields))

    def test_matching_schemas_return_empty_list(self):
        from pyspark.sql.types import StringType, StructField

        fields = [StructField("uuid", StringType())]
        assert self._call(fields, fields) == []

    def test_missing_expected_column_reported(self):
        from pyspark.sql.types import StringType, StructField, TimestampType

        actual = [StructField("uuid", StringType())]
        expected = [StructField("uuid", StringType()), StructField("ts_log", TimestampType())]
        errors = self._call(actual, expected)
        assert any("missing column 'ts_log'" in e for e in errors)

    def test_wrong_type_reported(self):
        from pyspark.sql.types import IntegerType, StringType, StructField

        actual = [StructField("uuid", IntegerType())]
        expected = [StructField("uuid", StringType())]
        errors = self._call(actual, expected)
        # Must name the column AND mention both types so the message is actionable
        assert any("uuid" in e and "string" in e and "int" in e for e in errors)

    def test_unexpected_extra_column_reported(self):
        from pyspark.sql.types import StringType, StructField

        actual = [StructField("uuid", StringType()), StructField("extra", StringType())]
        expected = [StructField("uuid", StringType())]
        errors = self._call(actual, expected)
        assert any("unexpected column 'extra'" in e for e in errors)


# ---------------------------------------------------------------------------
# validate_before_write — mocked DataFrame, no Spark required
# ---------------------------------------------------------------------------


class TestValidateBeforeWrite:
    """validate_before_write uses only df.count() and df.schema — both mockable."""

    def _mock_df(self, row_count: int, schema) -> MagicMock:
        df = MagicMock()
        df.count.return_value = row_count
        df.schema = schema
        return df

    def test_raises_on_empty_dataframe(self):
        from dags.agents.enrich_planner_emlio_logs.spark_jobs.load_planner_emlio_logs import (
            EXPECTED_SCHEMA,
            validate_before_write,
        )

        with pytest.raises(ValueError, match="empty"):
            validate_before_write(self._mock_df(0, EXPECTED_SCHEMA))

    def test_raises_on_schema_mismatch(self):
        from pyspark.sql.types import StringType, StructField, StructType
        from dags.agents.enrich_planner_emlio_logs.spark_jobs.load_planner_emlio_logs import (
            validate_before_write,
        )

        wrong_schema = StructType([StructField("wrong_col", StringType())])
        with pytest.raises(ValueError, match="Schema mismatch"):
            validate_before_write(self._mock_df(1, wrong_schema))

    def test_returns_row_count_on_valid_input(self):
        from dags.agents.enrich_planner_emlio_logs.spark_jobs.load_planner_emlio_logs import (
            EXPECTED_SCHEMA,
            validate_before_write,
        )

        assert validate_before_write(self._mock_df(42, EXPECTED_SCHEMA)) == 42

