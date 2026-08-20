"""Unit tests for the SFMC clean-layer contract checks and DLQ routing."""

import pytest
from pyspark.sql.types import (
    IntegerType,
    StringType,
    StructField,
    StructType,
)

from bietlejuice.base.sst.domains.sfmc.clean import quality as qy

DLQ_TIMESTAMP = "2026-08-06 03:00:00"

_SCHEMA = StructType(
    [
        StructField("event_id", StringType(), True),
        StructField("source_data_extension", StringType(), True),
        StructField("subscriber_key", StringType(), True),
        StructField("partition_date", StringType(), True),
    ]
)


def _df(spark, rows):
    return spark.createDataFrame(rows, _SCHEMA)


class TestConformRequiredColumns:
    def test_renames_the_normalized_event_id_back_to_the_contract_name(
        self, spark_session
    ):
        schema = StructType(
            [
                StructField("id_event", StringType(), True),
                StructField("source_data_extension", StringType(), True),
            ]
        )
        df = spark_session.createDataFrame([("E1", "send")], schema)

        out = qy.conform_required_columns(df)

        assert "event_id" in out.columns
        assert "id_event" not in out.columns
        assert out.collect()[0]["event_id"] == "E1"

    def test_keeps_an_existing_event_id_and_leaves_id_event_alone(self, spark_session):
        # A delivery that already uses the contract spelling must not have a
        # second, unrelated id_event column collapsed onto it.
        schema = StructType(
            [
                StructField("event_id", StringType(), True),
                StructField("id_event", StringType(), True),
                StructField("source_data_extension", StringType(), True),
            ]
        )
        df = spark_session.createDataFrame([("E1", "OTHER", "send")], schema)

        out = qy.conform_required_columns(df)

        assert out.columns == ["event_id", "id_event", "source_data_extension"]
        assert out.collect()[0]["event_id"] == "E1"

    @pytest.mark.parametrize("delivered_col", ["event_id", "source_data_extension"])
    def test_adds_a_contract_column_that_was_not_delivered(
        self, spark_session, delivered_col
    ):
        schema = StructType([StructField(delivered_col, StringType(), True)])
        df = spark_session.createDataFrame([("value",)], schema)

        out = qy.conform_required_columns(df)

        assert set(qy.GRAIN_COLS) <= set(out.columns)
        missing_col = next(c for c in qy.GRAIN_COLS if c != delivered_col)
        assert out.collect()[0][missing_col] is None

    def test_is_a_no_op_when_both_contract_columns_are_present(self, spark_session):
        df = _df(spark_session, [("E1", "send", "sub-1", "2026-08-05")])

        out = qy.conform_required_columns(df)

        assert out.columns == df.columns


class TestFlagQualityChecks:
    def test_adds_one_non_null_boolean_per_check(self, spark_session):
        df = _df(spark_session, [("E1", "send", "sub-1", "2026-08-05")])

        out = qy.flag_quality_checks(df).collect()[0]

        for check_col in qy.CHECK_COLS:
            assert out[check_col] is False

    @pytest.mark.parametrize("blank_value", [None, "", "   "])
    def test_flags_a_missing_or_blank_event_id(self, spark_session, blank_value):
        df = _df(spark_session, [(blank_value, "send", "sub-1", "2026-08-05")])

        out = qy.flag_quality_checks(df).collect()[0]

        assert out[qy.MISSING_EVENT_ID_CHECK] is True
        assert out[qy.MISSING_SOURCE_DATA_EXTENSION_CHECK] is False

    @pytest.mark.parametrize("blank_value", [None, "", "   "])
    def test_flags_a_missing_or_blank_source_data_extension(
        self, spark_session, blank_value
    ):
        df = _df(spark_session, [("E1", blank_value, "sub-1", "2026-08-05")])

        out = qy.flag_quality_checks(df).collect()[0]

        assert out[qy.MISSING_SOURCE_DATA_EXTENSION_CHECK] is True
        assert out[qy.MISSING_EVENT_ID_CHECK] is False

    def test_flags_a_numeric_event_id_as_present(self, spark_session):
        # The blank check casts to string, which must not turn 0 into "missing".
        schema = StructType(
            [
                StructField("event_id", IntegerType(), True),
                StructField("source_data_extension", StringType(), True),
            ]
        )
        df = spark_session.createDataFrame([(0, "send")], schema)

        out = qy.flag_quality_checks(df).collect()[0]

        assert out[qy.MISSING_EVENT_ID_CHECK] is False

    def test_flags_every_copy_of_a_duplicated_grain(self, spark_session):
        df = _df(
            spark_session,
            [
                ("E1", "send", "sub-1", "2026-08-05"),
                ("E1", "send", "sub-2", "2026-08-05"),
                ("E1", "send", "sub-3", "2026-08-05"),
                ("E2", "send", "sub-4", "2026-08-05"),
            ],
        )

        rows = qy.flag_quality_checks(df).collect()
        duplicated = [r for r in rows if r[qy.DUPLICATE_GRAIN_CHECK]]
        unique = [r for r in rows if not r[qy.DUPLICATE_GRAIN_CHECK]]

        assert len(duplicated) == 3
        assert {r["subscriber_key"] for r in duplicated} == {"sub-1", "sub-2", "sub-3"}
        assert len(unique) == 1
        assert unique[0]["event_id"] == "E2"

    def test_the_same_event_id_under_different_extensions_is_not_a_duplicate(
        self, spark_session
    ):
        df = _df(
            spark_session,
            [
                ("E1", "send", "sub-1", "2026-08-05"),
                ("E1", "return", "sub-2", "2026-08-05"),
            ],
        )

        rows = qy.flag_quality_checks(df).collect()

        assert all(row[qy.DUPLICATE_GRAIN_CHECK] is False for row in rows)

    def test_rows_without_a_grain_are_not_reported_as_duplicates(self, spark_session):
        # Two rows both missing event_id are two invalid rows, not the same
        # event twice; flagging them as duplicates would hide the real reason.
        df = _df(
            spark_session,
            [
                (None, "send", "sub-1", "2026-08-05"),
                (None, "send", "sub-2", "2026-08-05"),
            ],
        )

        rows = qy.flag_quality_checks(df).collect()

        assert all(row[qy.MISSING_EVENT_ID_CHECK] is True for row in rows)
        assert all(row[qy.DUPLICATE_GRAIN_CHECK] is False for row in rows)


class TestSplitCheckedRows:
    def test_accepted_rows_lose_the_flag_columns(self, spark_session):
        df = _df(spark_session, [("E1", "send", "sub-1", "2026-08-05")])
        flagged = qy.flag_quality_checks(df)

        accepted, rejected = qy.split_checked_rows(flagged, DLQ_TIMESTAMP)

        assert accepted.count() == 1
        assert not set(qy.CHECK_COLS) & set(accepted.columns)
        assert qy.TS_DLQ_COL not in accepted.columns
        assert rejected.count() == 0

    def test_rejected_rows_keep_their_flags_and_gain_the_dlq_timestamp(
        self, spark_session
    ):
        df = _df(
            spark_session,
            [
                ("E1", "send", "sub-1", "2026-08-05"),
                (None, "send", "sub-2", "2026-08-05"),
            ],
        )
        flagged = qy.flag_quality_checks(df)

        accepted, rejected = qy.split_checked_rows(flagged, DLQ_TIMESTAMP)

        assert accepted.count() == 1
        assert accepted.collect()[0]["event_id"] == "E1"

        rejected_rows = rejected.collect()
        assert len(rejected_rows) == 1
        assert rejected_rows[0][qy.MISSING_EVENT_ID_CHECK] is True
        assert rejected_rows[0][qy.TS_DLQ_COL] == DLQ_TIMESTAMP
        assert set(qy.CHECK_COLS) <= set(rejected.columns)

    def test_a_row_failing_several_checks_is_rejected_once_with_every_flag(
        self, spark_session
    ):
        df = _df(
            spark_session,
            [
                (None, None, "sub-1", "2026-08-05"),
            ],
        )
        flagged = qy.flag_quality_checks(df)

        accepted, rejected = qy.split_checked_rows(flagged, DLQ_TIMESTAMP)

        assert accepted.count() == 0
        rejected_rows = rejected.collect()
        assert len(rejected_rows) == 1
        assert rejected_rows[0][qy.MISSING_EVENT_ID_CHECK] is True
        assert rejected_rows[0][qy.MISSING_SOURCE_DATA_EXTENSION_CHECK] is True

    def test_no_copy_of_a_duplicated_grain_reaches_the_accepted_rows(
        self, spark_session
    ):
        df = _df(
            spark_session,
            [
                ("E1", "send", "sub-1", "2026-08-05"),
                ("E1", "send", "sub-2", "2026-08-05"),
                ("E2", "send", "sub-3", "2026-08-05"),
            ],
        )
        flagged = qy.flag_quality_checks(df)

        accepted, rejected = qy.split_checked_rows(flagged, DLQ_TIMESTAMP)

        assert [row["event_id"] for row in accepted.collect()] == ["E2"]
        assert rejected.count() == 2
        assert all(row[qy.DUPLICATE_GRAIN_CHECK] for row in rejected.collect())

    def test_honours_an_explicit_check_subset(self, spark_session):
        df = _df(
            spark_session,
            [
                ("E1", "send", "sub-1", "2026-08-05"),
                ("E1", "send", "sub-2", "2026-08-05"),
            ],
        )
        flagged = qy.flag_quality_checks(df)

        accepted, rejected = qy.split_checked_rows(
            flagged, DLQ_TIMESTAMP, check_cols=[qy.MISSING_EVENT_ID_CHECK]
        )

        # Duplicates pass when the duplicate check is not part of the subset.
        assert accepted.count() == 2
        assert rejected.count() == 0
