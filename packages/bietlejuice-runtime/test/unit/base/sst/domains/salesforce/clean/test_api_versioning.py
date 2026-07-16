"""Unit tests for the Salesforce API_v2 clean SCD Type 2 transforms."""

from unittest import mock

import pytest
from pyspark.sql.types import (
    BooleanType,
    StringType,
    StructField,
    StructType,
)

from bietlejuice.base.sst.domains.salesforce.clean import api_versioning as av

# --- schemas -----------------------------------------------------------------

# Shape of a conformed daily snapshot (post conform_api_clean, pre versioning).
_CONFORMED_SCHEMA = StructType(
    [
        StructField("id_record", StringType(), True),
        StructField("system_modstamp", StringType(), True),
        StructField("created_date", StringType(), True),
        StructField("is_deleted", BooleanType(), True),
        StructField("subject", StringType(), True),
        StructField("partition_date", StringType(), True),
    ]
)

# Shape of an existing clean row (adds the versioning columns get_versioning_df emits).
_CLEAN_SCHEMA = StructType(
    _CONFORMED_SCHEMA.fields
    + [
        StructField("_effective_timestamp", StringType(), True),
        StructField("_expired_timestamp", StringType(), True),
        StructField("_is_current", BooleanType(), True),
        StructField("_created_at", StringType(), True),
        StructField("_last_updated_at", StringType(), True),
    ]
)

_HIGH_DATE_PREFIX = "9999-12-31"


def _conformed(spark, rows):
    return spark.createDataFrame(rows, _CONFORMED_SCHEMA)


def _prior_clean(spark, rows):
    return spark.createDataFrame(rows, _CLEAN_SCHEMA)


def _by_id(df):
    return {r["id_record"]: r for r in df.collect()}


# --- conform_api_clean -------------------------------------------------------


class TestConformApiClean:
    @pytest.fixture
    def raw_df(self, spark_session):
        schema = StructType(
            [
                StructField("id_record", StringType(), True),
                StructField("WhoId", StringType(), True),
                StructField("Subject", StringType(), True),
                StructField("IsDeleted", BooleanType(), True),
                StructField("CreatedDate", StringType(), True),
                StructField("LastModifiedDate", StringType(), True),
                StructField("SystemModstamp", StringType(), True),
                StructField("entity_type", StringType(), True),
                StructField("ts_load", StringType(), True),
                StructField("partition_date", StringType(), True),
            ]
        )
        rows = [
            (
                "A",
                "W1",
                "hello",
                False,
                "2026-06-01 10:00:00.123",
                "2026-06-01 10:00:00.123",
                "2026-06-01 10:00:00.123",
                "Task",
                "2026-06-02 03:00:00",
                "2026-06-01",
            ),
            # duplicate id within the partition -> must be collapsed to one row
            (
                "A",
                "W1",
                "hello",
                False,
                "2026-06-01 10:00:00.123",
                "2026-06-01 10:00:00.123",
                "2026-06-01 10:00:00.123",
                "Task",
                "2026-06-02 03:00:00",
                "2026-06-01",
            ),
        ]
        return spark_session.createDataFrame(rows, schema)

    def test_normalizes_names_and_drops_raw_only_cols(self, raw_df):
        out = av.conform_api_clean(raw_df, "id_record")
        cols = set(out.columns)
        # snake_cased; WhoId -> id_who; IsDeleted -> is_deleted; SystemModstamp -> system_modstamp
        assert {
            "id_record",
            "id_who",
            "subject",
            "is_deleted",
            "created_date",
            "last_modified_date",
            "system_modstamp",
            "partition_date",
        } <= cols
        # raw-only lineage columns removed
        assert "entity_type" not in cols
        assert "ts_load" not in cols

    def test_standardizes_timestamps_and_dedupes_by_id(self, raw_df):
        out = av.conform_api_clean(raw_df, "id_record").collect()
        assert len(out) == 1  # the duplicate id_record collapsed
        # millis truncated to the canonical "yyyy-MM-dd HH:mm:ss" format
        assert out[0]["system_modstamp"] == "2026-06-01 10:00:00"
        assert out[0]["created_date"] == "2026-06-01 10:00:00"


# --- build_api_versioned_df: bootstrap (no target) ---------------------------


class TestBootstrapVersioning:
    @mock.patch.object(av, "_table_exists", return_value=False)
    def test_single_record_is_current_with_open_expiry(
        self, _mock_exists, spark_session
    ):
        conformed = _conformed(
            spark_session,
            [
                (
                    "A",
                    "2026-06-01 00:00:00",
                    "2026-05-01 00:00:00",
                    False,
                    "s",
                    "2026-06-01",
                )
            ],
        )

        out = av.build_api_versioned_df(
            spark_session, conformed, "nope.nope", "id_record", "system_modstamp"
        ).collect()

        assert len(out) == 1
        row = out[0]
        assert row["_is_current"] is True
        assert row["_effective_timestamp"] == "2026-06-01 00:00:00"
        assert str(row["_expired_timestamp"]).startswith(_HIGH_DATE_PREFIX)

    @mock.patch.object(av, "_table_exists", return_value=False)
    def test_two_distinct_ids_each_current(self, _mock_exists, spark_session):
        conformed = _conformed(
            spark_session,
            [
                (
                    "A",
                    "2026-06-01 00:00:00",
                    "2026-05-01 00:00:00",
                    False,
                    "s",
                    "2026-06-01",
                ),
                (
                    "B",
                    "2026-06-01 00:00:00",
                    "2026-05-01 00:00:00",
                    False,
                    "s",
                    "2026-06-01",
                ),
            ],
        )

        rows = _by_id(
            av.build_api_versioned_df(
                spark_session, conformed, "nope.nope", "id_record", "system_modstamp"
            )
        )

        assert rows["A"]["_is_current"] is True
        assert rows["B"]["_is_current"] is True


# --- build_api_versioned_df: incremental (existing target) -------------------


class TestIncrementalVersioning:
    def _run(self, spark_session, prior_rows, today_rows):
        """Drive build_api_versioned_df through the incremental branch with a mocked target."""
        prior_df = _prior_clean(spark_session, prior_rows)
        today_df = _conformed(spark_session, today_rows)

        mock_spark = mock.MagicMock()
        mock_spark.read.table.return_value.columns = prior_df.columns

        with (
            mock.patch.object(av, "_table_exists", return_value=True),
            mock.patch.object(av, "get_rows_to_update", return_value=prior_df),
        ):
            return av.build_api_versioned_df(
                mock_spark, today_df, "sc.tbl", "id_record", "system_modstamp"
            )

    def test_change_closes_prior_and_keeps_one_current(self, spark_session):
        prior = [
            (
                "A",
                "2026-06-01 00:00:00",
                "2026-05-01 00:00:00",
                False,
                "old",
                "2026-06-01",
                "2026-06-01 00:00:00",
                "9999-12-31 23:59:59",
                True,
                "2026-05-01 00:00:00",
                "2026-06-01 03:00:00",
            )
        ]
        today = [
            (
                "A",
                "2026-06-05 00:00:00",
                "2026-05-01 00:00:00",
                False,
                "new",
                "2026-06-05",
            )
        ]

        result = self._run(spark_session, prior, today).collect()

        assert len(result) == 2
        current = [r for r in result if r["_is_current"]]
        expired = [r for r in result if not r["_is_current"]]
        assert len(current) == 1
        assert current[0]["_effective_timestamp"] == "2026-06-05 00:00:00"
        assert current[0]["subject"] == "new"
        # prior version closed exactly at the new version's effective timestamp
        assert expired[0]["_effective_timestamp"] == "2026-06-01 00:00:00"
        assert expired[0]["_expired_timestamp"] == "2026-06-05 00:00:00"

    def test_unchanged_modstamp_produces_no_duplicate_version(self, spark_session):
        prior = [
            (
                "A",
                "2026-06-01 00:00:00",
                "2026-05-01 00:00:00",
                False,
                "same",
                "2026-06-01",
                "2026-06-01 00:00:00",
                "9999-12-31 23:59:59",
                True,
                "2026-05-01 00:00:00",
                "2026-06-01 03:00:00",
            )
        ]
        today = [
            (
                "A",
                "2026-06-01 00:00:00",
                "2026-05-01 00:00:00",
                False,
                "same",
                "2026-06-05",
            )
        ]

        result = self._run(spark_session, prior, today).collect()

        assert len(result) == 1
        assert result[0]["_is_current"] is True

    def test_delete_creates_closing_current_version(self, spark_session):
        prior = [
            (
                "A",
                "2026-06-01 00:00:00",
                "2026-05-01 00:00:00",
                False,
                "live",
                "2026-06-01",
                "2026-06-01 00:00:00",
                "9999-12-31 23:59:59",
                True,
                "2026-05-01 00:00:00",
                "2026-06-01 03:00:00",
            )
        ]
        today = [
            (
                "A",
                "2026-06-07 00:00:00",
                "2026-05-01 00:00:00",
                True,
                "live",
                "2026-06-07",
            )
        ]

        result = self._run(spark_session, prior, today).collect()

        current = [r for r in result if r["_is_current"]]
        assert len(current) == 1
        assert current[0]["is_deleted"] is True
        assert current[0]["_effective_timestamp"] == "2026-06-07 00:00:00"
