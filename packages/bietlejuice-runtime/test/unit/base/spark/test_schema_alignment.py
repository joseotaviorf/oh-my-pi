"""Unit tests for string -> timestamp/date alignment against a Delta target."""

from unittest import mock

import pytest
from pyspark.sql.types import (
    DateType,
    DecimalType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampNTZType,
    TimestampType,
)

from bietlejuice.base.spark.schema_alignment import (
    AUDIT_NULLS_CONF,
    align_source_to_target,
    apply_alignment,
    audit_alignment_nulls,
    plan_alignment,
)


def _schema(*fields):
    return StructType([StructField(name, dtype, True) for name, dtype in fields])


class TestPlanAlignment:
    def test_string_source_to_timestamp_target_is_planned(self):
        source = _schema(("id", LongType()), ("created_at", StringType()))
        target = _schema(("id", LongType()), ("created_at", TimestampType()))

        assert plan_alignment(source, target) == [("created_at", TimestampType())]

    def test_string_source_to_date_target_is_planned(self):
        source = _schema(("reference_day", StringType()))
        target = _schema(("reference_day", DateType()))

        assert plan_alignment(source, target) == [("reference_day", DateType())]

    def test_timestamp_ntz_target_is_planned(self):
        source = _schema(("created_at", StringType()))
        target = _schema(("created_at", TimestampNTZType()))

        assert plan_alignment(source, target) == [("created_at", TimestampNTZType())]

    def test_matching_types_are_not_planned(self):
        source = _schema(("created_at", TimestampType()), ("name", StringType()))
        target = _schema(("created_at", TimestampType()), ("name", StringType()))

        assert plan_alignment(source, target) == []

    def test_non_temporal_target_is_left_alone(self):
        """Scope is deliberately narrow: only dates were coerced to string.

        A string -> decimal or string -> struct mismatch means something else is
        wrong and belongs to schema evolution or a human, not to this cast.
        """
        source = _schema(("amount", StringType()), ("tags", StringType()))
        target = _schema(
            ("amount", DecimalType(17, 2)),
            ("tags", StructType([StructField("a", StringType(), True)])),
        )

        assert plan_alignment(source, target) == []

    def test_non_string_source_is_left_alone(self):
        """A long where the target wants a timestamp is not this cast's problem."""
        source = _schema(("created_at", LongType()))
        target = _schema(("created_at", TimestampType()))

        assert plan_alignment(source, target) == []

    def test_column_absent_from_target_is_skipped(self):
        """New source columns are handled by autoMerge schema evolution."""
        source = _schema(("created_at", StringType()), ("brand_new", StringType()))
        target = _schema(("created_at", TimestampType()))

        assert plan_alignment(source, target) == [("created_at", TimestampType())]

    def test_names_match_case_insensitively_keeping_source_spelling(self):
        """Glue lower-cases column names; Delta keeps the registered spelling."""
        source = _schema(("CreatedAt", StringType()))
        target = _schema(("createdat", TimestampType()))

        assert plan_alignment(source, target) == [("CreatedAt", TimestampType())]

    def test_case_colliding_source_columns_are_skipped(self):
        """Which of the two the target means is unknowable, so cast neither."""
        source = StructType(
            [
                StructField("created_at", StringType(), True),
                StructField("Created_At", StringType(), True),
            ]
        )
        target = _schema(("created_at", TimestampType()))

        assert plan_alignment(source, target) == []

    def test_empty_schemas_produce_no_plan(self):
        assert plan_alignment(StructType(), StructType()) == []

    def test_plan_follows_source_column_order(self):
        source = _schema(
            ("z_at", StringType()),
            ("id", LongType()),
            ("a_at", StringType()),
        )
        target = _schema(("a_at", DateType()), ("z_at", TimestampType()))

        assert [name for name, _ in plan_alignment(source, target)] == ["z_at", "a_at"]


class TestApplyAlignment:
    def test_casts_iso8601_string_to_timestamp(self, spark_session):
        source_df = spark_session.createDataFrame(
            [("1", "2026-08-05T12:34:56Z")],
            _schema(("id", StringType()), ("created_at", StringType())),
        )

        aligned = apply_alignment(source_df, [("created_at", TimestampType())])

        assert dict(aligned.dtypes)["created_at"] == "timestamp"
        assert aligned.collect()[0]["created_at"] is not None
        # Untouched columns keep their type and position.
        assert aligned.columns == ["id", "created_at"]
        assert dict(aligned.dtypes)["id"] == "string"

    def test_handles_column_name_containing_a_dot(self, spark_session):
        """Raw JSON really does produce names like ``action_performed_date.1``."""
        source_df = spark_session.createDataFrame(
            [("2026-08-05",)],
            _schema(("action_performed_date.1", StringType())),
        )

        aligned = apply_alignment(source_df, [("action_performed_date.1", DateType())])

        assert dict(aligned.dtypes)["action_performed_date.1"] == "date"
        assert aligned.collect()[0][0] is not None

    def test_empty_plan_returns_the_same_dataframe(self, spark_session):
        source_df = spark_session.createDataFrame(
            [("1",)], _schema(("id", StringType()))
        )

        assert apply_alignment(source_df, []) is source_df


class TestAuditAlignmentNulls:
    def test_counts_only_non_null_values_the_cast_loses(self, spark_session):
        source_df = spark_session.createDataFrame(
            [
                ("2026-08-05T12:34:56Z", "2026-08-05"),
                ("not a timestamp", "2026-08-06"),
                (None, "nonsense"),
            ],
            _schema(("created_at", StringType()), ("day", StringType())),
        )

        deltas = audit_alignment_nulls(
            source_df,
            [("created_at", TimestampType()), ("day", DateType())],
        )

        # The already-null row is not a loss; the unparseable ones are.
        assert deltas == {"created_at": 1, "day": 1}

    def test_reports_zero_when_every_value_parses(self, spark_session):
        source_df = spark_session.createDataFrame(
            [("2026-08-05T12:34:56Z",)], _schema(("created_at", StringType()))
        )

        deltas = audit_alignment_nulls(source_df, [("created_at", TimestampType())])

        assert deltas == {"created_at": 0}

    def test_empty_source_reports_zero(self, spark_session):
        source_df = spark_session.createDataFrame(
            [], _schema(("created_at", StringType()))
        )

        deltas = audit_alignment_nulls(source_df, [("created_at", TimestampType())])

        assert deltas == {"created_at": 0}

    def test_uses_a_single_aggregation(self, spark_session):
        """One pass over the source regardless of how many columns are aligned."""
        source_df = spark_session.createDataFrame(
            [("2026-08-05T12:34:56Z", "2026-08-05")],
            _schema(("created_at", StringType()), ("day", StringType())),
        )
        with mock.patch.object(source_df, "agg", wraps=source_df.agg) as agg_spy:
            audit_alignment_nulls(
                source_df, [("created_at", TimestampType()), ("day", DateType())]
            )

        agg_spy.assert_called_once()
        assert len(agg_spy.call_args.args) == 2

    def test_empty_plan_skips_spark_entirely(self):
        source_df = mock.MagicMock()

        assert audit_alignment_nulls(source_df, []) == {}
        source_df.agg.assert_not_called()


class TestAlignSourceToTarget:
    @pytest.fixture
    def spark_with_target(self, spark_session):
        """SparkSession whose ``read.table`` returns a timestamp-typed target."""
        target_df = spark_session.createDataFrame(
            [], _schema(("id", StringType()), ("created_at", TimestampType()))
        )
        spark = mock.MagicMock()
        spark.read.table.return_value = target_df
        spark.conf.get.return_value = "true"
        return spark

    @pytest.fixture
    def string_source_df(self, spark_session):
        return spark_session.createDataFrame(
            [("1", "2026-08-05T12:34:56Z")],
            _schema(("id", StringType()), ("created_at", StringType())),
        )

    def test_casts_against_the_registered_target_schema(
        self, spark_with_target, string_source_df
    ):
        aligned = align_source_to_target(
            spark_with_target, string_source_df, "db.clean_table"
        )

        spark_with_target.read.table.assert_called_once_with("db.clean_table")
        assert dict(aligned.dtypes)["created_at"] == "timestamp"

    def test_unreadable_target_leaves_the_source_untouched(self, string_source_df):
        """A load must never break because the alignment could not run."""
        spark = mock.MagicMock()
        spark.read.table.side_effect = RuntimeError("table not found")

        aligned = align_source_to_target(spark, string_source_df, "db.clean_table")

        assert aligned is string_source_df

    def test_matching_schema_returns_the_source_unchanged(
        self, spark_session, spark_with_target
    ):
        source_df = spark_session.createDataFrame(
            [("1", None)],
            _schema(("id", StringType()), ("created_at", TimestampType())),
        )

        aligned = align_source_to_target(spark_with_target, source_df, "db.clean_table")

        assert aligned is source_df

    def test_null_audit_runs_by_default(self, spark_with_target, string_source_df):
        with mock.patch(
            "bietlejuice.base.spark.schema_alignment.audit_alignment_nulls",
            return_value={"created_at": 0},
        ) as audit:
            align_source_to_target(
                spark_with_target, string_source_df, "db.clean_table"
            )

        audit.assert_called_once()

    def test_null_audit_can_be_disabled_by_spark_conf(
        self, spark_with_target, string_source_df
    ):
        spark_with_target.conf.get.return_value = "false"

        with mock.patch(
            "bietlejuice.base.spark.schema_alignment.audit_alignment_nulls"
        ) as audit:
            aligned = align_source_to_target(
                spark_with_target, string_source_df, "db.clean_table"
            )

        audit.assert_not_called()
        spark_with_target.conf.get.assert_called_with(AUDIT_NULLS_CONF, "true")
        # The cast still happens; only the extra pass is skipped.
        assert dict(aligned.dtypes)["created_at"] == "timestamp"

    def test_null_audit_can_be_disabled_by_argument(
        self, spark_with_target, string_source_df
    ):
        with mock.patch(
            "bietlejuice.base.spark.schema_alignment.audit_alignment_nulls"
        ) as audit:
            align_source_to_target(
                spark_with_target,
                string_source_df,
                "db.clean_table",
                audit_nulls=False,
            )

        audit.assert_not_called()

    def test_failing_null_audit_still_returns_the_aligned_dataframe(
        self, spark_with_target, string_source_df
    ):
        with mock.patch(
            "bietlejuice.base.spark.schema_alignment.audit_alignment_nulls",
            side_effect=RuntimeError("boom"),
        ):
            aligned = align_source_to_target(
                spark_with_target, string_source_df, "db.clean_table"
            )

        assert dict(aligned.dtypes)["created_at"] == "timestamp"

    def test_failing_cast_falls_back_to_the_source(
        self, spark_with_target, string_source_df
    ):
        with mock.patch(
            "bietlejuice.base.spark.schema_alignment.apply_alignment",
            side_effect=RuntimeError("boom"),
        ):
            aligned = align_source_to_target(
                spark_with_target, string_source_df, "db.clean_table"
            )

        assert aligned is string_source_df
