from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from pyspark.sql.types import (
    BooleanType,
    StringType,
    StructField,
    StructType,
)

from bietlejuice.base.sst.core.observability.metrics import (
    build_quality_check_metric_dataframe,
    save_quality_check_metric,
    save_scd_change_metric,
    save_table_metadata_metric,
    save_volume_metric,
)


class DummyExpr:
    def alias(self, _):
        return self

    def cast(self, _):
        return self


def test_save_volume_metric_writes_aggregated_rows_for_non_empty_df():
    """Test that the save_volume_metric function writes aggregated rows
    for a non-empty DataFrame.
    Validates the function writes the correct number of rows and the correct columns
    when the DataFrame is not empty.
    """
    spark = MagicMock()
    metric_df = MagicMock()
    metric_df.isEmpty.return_value = False
    metric_df.withColumn.return_value = metric_df
    metric_df.select.return_value = metric_df

    grouped_df = MagicMock()
    grouped_df.agg.return_value = metric_df

    df = MagicMock()
    df.groupby.return_value = grouped_df

    with (
        patch(
            "bietlejuice.base.sst.core.observability.metrics.validate_and_write"
        ) as mock_validate_and_write,
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.coalesce",
            return_value=DummyExpr(),
        ),
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.count",
            return_value=DummyExpr(),
        ),
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.lit",
            return_value=DummyExpr(),
        ),
    ):
        save_volume_metric(
            spark=spark,
            df=df,
            grain=["partition_date", "partition_hour"],
            metric_name="events_volume",
            table_name="datalake_salesforce_clean.events",
            env="forno",
            layer="clean",
            partition_cols=["partition_date", "partition_hour"],
            table_location="s3://bucket/path/to/table",
        )

    assert mock_validate_and_write.call_count == 1
    assert mock_validate_and_write.call_args.kwargs["df"] == metric_df


def test_save_volume_metric_writes_zero_row_metric_for_empty_df():
    spark = MagicMock()
    initial_metric_df = MagicMock()
    initial_metric_df.isEmpty.return_value = True
    initial_metric_df.withColumn.return_value = initial_metric_df
    initial_metric_df.select.return_value = initial_metric_df

    fallback_df = MagicMock()
    fallback_df.withColumn.return_value = fallback_df
    fallback_df.select.return_value = fallback_df
    spark.range.return_value = fallback_df

    grouped_df = MagicMock()
    grouped_df.agg.return_value = initial_metric_df

    empty_df = MagicMock()
    empty_df.groupby.return_value = grouped_df
    empty_df.schema.fields = [
        SimpleNamespace(name="partition_date", dataType=StringType()),
        SimpleNamespace(name="partition_hour", dataType=StringType()),
    ]

    with (
        patch(
            "bietlejuice.base.sst.core.observability.metrics.validate_and_write"
        ) as mock_validate_and_write,
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.coalesce",
            return_value=DummyExpr(),
        ),
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.count",
            return_value=DummyExpr(),
        ),
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.lit",
            return_value=DummyExpr(),
        ),
    ):
        save_volume_metric(
            spark=spark,
            df=empty_df,
            grain=["partition_date", "partition_hour"],
            metric_name="events_volume",
            table_name="datalake_salesforce_clean.events",
            env="forno",
            layer="clean",
            partition_cols=["partition_date", "partition_hour"],
            table_location="s3://bucket/path/to/table",
        )

    assert mock_validate_and_write.call_count == 1
    assert mock_validate_and_write.call_args.kwargs["df"] == fallback_df
    assert fallback_df.withColumn.call_count >= 9


def test_save_volume_metric_uses_fallback_grain_values_for_empty_df():
    # A caller that already knows which partition it processed (e.g. it just
    # wrote it, empty on purpose) can pass that value through so the zero-row
    # metric lands under the real partition instead of a NULL one.
    spark = MagicMock()
    initial_metric_df = MagicMock()
    initial_metric_df.isEmpty.return_value = True
    initial_metric_df.withColumn.return_value = initial_metric_df
    initial_metric_df.select.return_value = initial_metric_df

    fallback_df = MagicMock()
    fallback_df.withColumn.return_value = fallback_df
    fallback_df.select.return_value = fallback_df
    spark.range.return_value = fallback_df

    grouped_df = MagicMock()
    grouped_df.agg.return_value = initial_metric_df

    empty_df = MagicMock()
    empty_df.groupby.return_value = grouped_df
    empty_df.schema.fields = [
        SimpleNamespace(name="partition_date", dataType=StringType()),
    ]

    with (
        patch("bietlejuice.base.sst.core.observability.metrics.validate_and_write"),
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.coalesce",
            return_value=DummyExpr(),
        ),
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.count",
            return_value=DummyExpr(),
        ),
        patch("bietlejuice.base.sst.core.observability.metrics.F.lit") as mock_lit,
    ):
        mock_lit.return_value = DummyExpr()

        save_volume_metric(
            spark=spark,
            df=empty_df,
            grain=["partition_date"],
            metric_name="clean_volume",
            table_name="datalake_sfmc_clean.send",
            env="forno",
            layer="clean",
            partition_cols=["partition_date"],
            table_location="s3://bucket/path/to/table",
            fallback_grain_values={"partition_date": "2026-08-05"},
        )

    mock_lit.assert_any_call("2026-08-05")


def test_save_volume_metric_records_zero_row_when_df_is_none():
    # A caller that bailed out before building a frame at all still has to
    # record row_count = 0, so an absent row unambiguously means the job never
    # ran. There is no dataframe to read grain types from, so the grain comes
    # entirely from fallback_grain_values and is left untyped.
    spark = MagicMock()

    fallback_df = MagicMock()
    fallback_df.withColumn.return_value = fallback_df
    fallback_df.select.return_value = fallback_df
    spark.range.return_value = fallback_df

    with (
        patch(
            "bietlejuice.base.sst.core.observability.metrics.validate_and_write"
        ) as mock_write,
        patch("bietlejuice.base.sst.core.observability.metrics.F.lit") as mock_lit,
    ):
        mock_lit.return_value = DummyExpr()

        save_volume_metric(
            spark=spark,
            df=None,
            grain=["partition_date", "partition_hour", "event_type"],
            metric_name="events_type_volume",
            table_name="events_case",
            env="prod",
            layer="raw",
            partition_cols=["partition_date", "partition_hour"],
            table_location="s3a://bucket/sst_metrics/events_type_volume",
            fallback_grain_values={
                "partition_date": "2026-08-21",
                "partition_hour": "10",
                "event_type": "DLQ_RECOVERY",
            },
        )

    # Synthetic single row, not an aggregation over a frame.
    spark.range.assert_called_once_with(1)
    for value in ("2026-08-21", "10", "DLQ_RECOVERY"):
        mock_lit.assert_any_call(value)
    assert mock_write.call_count == 1
    write_kwargs = mock_write.call_args.kwargs
    assert write_kwargs["target_table"] == "datalake_sst_metrics.events_type_volume"
    assert write_kwargs["append"] is True


def test_save_scd_change_metric_writes_to_metric_name_table():
    """save_scd_change_metric writes one aggregated row to
    datalake_sst_metrics.<metric_name>, partitioned by source_table +
    partition keys so a rerun overwrites its own row.
    """
    spark = MagicMock()

    metric_df = MagicMock()
    df = MagicMock()
    df.agg.return_value = metric_df

    with (
        patch(
            "bietlejuice.base.sst.core.observability.metrics.save_metric_dataframe"
        ) as mock_save_metric_dataframe,
        patch(
            "bietlejuice.base.sst.core.observability.metrics.build_metric_dataframe",
            return_value=metric_df,
        ),
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.count",
            return_value=DummyExpr(),
        ),
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.sum",
            return_value=DummyExpr(),
        ),
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.when",
            return_value=MagicMock(),
        ),
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.col",
            return_value=MagicMock(),
        ),
    ):
        result = save_scd_change_metric(
            spark=spark,
            df=df,
            bucket="my-bucket",
            metric_name="core_model_scd_changes",
            target_table="core_support_journey.analyst",
            partition_date="2026-08-11",
            partition_hour="19",
            env="prod",
            layer="core",
        )

    assert result == metric_df
    assert mock_save_metric_dataframe.call_count == 1
    call_kwargs = mock_save_metric_dataframe.call_args.kwargs
    assert call_kwargs["df"] == metric_df
    assert call_kwargs["bucket"] == "my-bucket"
    assert call_kwargs["metric_table"] == "core_model_scd_changes"
    assert call_kwargs["partition_cols"] == [
        "source_table",
        "partition_date",
        "partition_hour",
    ]
    assert call_kwargs["partition_filter_values"] == {
        "source_table": "core_support_journey.analyst",
        "partition_date": "2026-08-11",
        "partition_hour": "19",
    }


def test_save_scd_change_metric_builds_inserted_and_updated_counts():
    """The metric row carries scd_change category metadata and the aggregation
    produces row_count, inserted_count (is_current true) and updated_count
    (is_current false).
    """
    spark = MagicMock()

    metric_df = MagicMock()
    df = MagicMock()
    df.agg.return_value = metric_df

    captured = {}

    def _capture_build(df, metric_values, select_columns):
        captured["metric_values"] = metric_values
        captured["select_columns"] = select_columns
        return metric_df

    with (
        patch("bietlejuice.base.sst.core.observability.metrics.save_metric_dataframe"),
        patch(
            "bietlejuice.base.sst.core.observability.metrics.build_metric_dataframe",
            side_effect=_capture_build,
        ),
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.count",
            return_value=DummyExpr(),
        ),
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.sum",
            return_value=DummyExpr(),
        ),
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.when",
            return_value=MagicMock(),
        ),
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.col",
            return_value=MagicMock(),
        ) as mock_col,
    ):
        save_scd_change_metric(
            spark=spark,
            df=df,
            bucket="my-bucket",
            metric_name="core_model_scd_changes",
            target_table="core_support_journey.analyst",
            partition_date="2026-08-11",
            partition_hour="19",
            env="forno",
            layer="core",
        )

    metric_values = captured["metric_values"]
    assert metric_values["metric_category"] == "scd_change"
    assert metric_values["metric_name"] == "core_model_scd_changes"
    assert metric_values["source_table"] == "core_support_journey.analyst"
    assert metric_values["environment"] == "forno"
    assert metric_values["layer"] == "core"

    assert "row_count" in captured["select_columns"]
    assert "inserted_count" in captured["select_columns"]
    assert "updated_count" in captured["select_columns"]
    mock_col.assert_any_call("_is_current")


def test_save_table_metadata_metric_writes_single_table_partitioned_by_source_table():
    """save_table_metadata_metric writes one row per source table to the shared
    datalake_sst_metrics.table_metadata table, partitioned by source_table +
    partition keys.
    """
    spark = MagicMock()

    metric_df = MagicMock()
    metric_df.withColumn.return_value = metric_df
    metric_df.select.return_value = metric_df
    spark.range.return_value = metric_df

    with (
        patch(
            "bietlejuice.base.sst.core.observability.metrics.save_metric_dataframe"
        ) as mock_save_metric_dataframe,
        patch(
            "bietlejuice.base.sst.core.observability.metrics.F.lit",
            return_value=MagicMock(),
        ),
    ):
        save_table_metadata_metric(
            spark=spark,
            table_name="datalake_salesforce_clean.events",
            new_cols=["status"],
            env="forno",
            layer="clean",
            bucket="my-bucket",
            partition_date="2024-01-01",
            partition_hour="00",
        )

    assert mock_save_metric_dataframe.call_count == 1
    call_kwargs = mock_save_metric_dataframe.call_args.kwargs
    assert call_kwargs["df"] == metric_df
    assert call_kwargs["bucket"] == "my-bucket"
    assert call_kwargs["metric_table"] == "table_metadata"
    assert call_kwargs["partition_cols"] == [
        "source_table",
        "partition_date",
        "partition_hour",
    ]
    assert call_kwargs["partition_filter_values"] == {
        "source_table": "datalake_salesforce_clean.events",
        "partition_date": "2024-01-01",
        "partition_hour": "00",
    }


def test_save_table_metadata_metric_records_new_cols_as_sorted_list():
    """new_cols is passed (sorted) as a list in metric_values so F.lit materializes
    it as an array column; the metric row also carries new_cols_count.
    """
    spark = MagicMock()

    metric_df = MagicMock()
    metric_df.withColumn.return_value = metric_df
    metric_df.select.return_value = metric_df
    spark.range.return_value = metric_df

    captured = {}

    def _capture_build(df, metric_values, select_columns):
        captured["metric_values"] = metric_values
        captured["select_columns"] = select_columns
        return metric_df

    with (
        patch("bietlejuice.base.sst.core.observability.metrics.save_metric_dataframe"),
        patch(
            "bietlejuice.base.sst.core.observability.metrics.build_metric_dataframe",
            side_effect=_capture_build,
        ),
    ):
        save_table_metadata_metric(
            spark=spark,
            table_name="datalake_salesforce_clean.events",
            new_cols=["status", "owner"],
            env="forno",
            layer="clean",
            bucket="my-bucket",
            partition_date="2024-01-01",
            partition_hour="00",
        )

    metric_values = captured["metric_values"]
    assert metric_values["source_table"] == "datalake_salesforce_clean.events"
    assert metric_values["new_cols"] == ["owner", "status"]
    assert metric_values["new_cols_count"] == 2
    assert "new_cols" in captured["select_columns"]


def test_save_table_metadata_metric_handles_none_new_cols():
    """new_cols=None is treated as an empty list (zero new columns)."""
    spark = MagicMock()

    metric_df = MagicMock()
    metric_df.withColumn.return_value = metric_df
    metric_df.select.return_value = metric_df
    spark.range.return_value = metric_df

    captured = {}

    def _capture_build(df, metric_values, select_columns):
        captured["metric_values"] = metric_values
        return metric_df

    with (
        patch(
            "bietlejuice.base.sst.core.observability.metrics.save_metric_dataframe"
        ) as mock_save_metric_dataframe,
        patch(
            "bietlejuice.base.sst.core.observability.metrics.build_metric_dataframe",
            side_effect=_capture_build,
        ),
    ):
        save_table_metadata_metric(
            spark=spark,
            table_name="datalake_ebdb_clean.contract",
            new_cols=None,
            env="prod",
            layer="clean",
            bucket="my-bucket",
            partition_date="2024-01-01",
            partition_hour="00",
        )

    assert mock_save_metric_dataframe.call_count == 1
    assert captured["metric_values"]["new_cols"] == []
    assert captured["metric_values"]["new_cols_count"] == 0


CHECK_COLS = [
    "failed_missing_event_id",
    "failed_missing_source_data_extension",
    "failed_duplicate_grain",
]

_FLAGGED_SCHEMA = StructType(
    [
        StructField("event_id", StringType(), True),
        StructField("failed_missing_event_id", BooleanType(), False),
        StructField("failed_missing_source_data_extension", BooleanType(), False),
        StructField("failed_duplicate_grain", BooleanType(), False),
    ]
)


def _flagged_df(spark_session, rows):
    return spark_session.createDataFrame(rows, _FLAGGED_SCHEMA)


def _metric_by_check(metric_df):
    return {row["check_name"]: row for row in metric_df.collect()}


def test_build_quality_check_metric_dataframe_counts_failures_per_check(spark_session):
    """One metric row per check, each carrying its own failure count and the
    shared total, so a failure rate can be read straight off the table."""
    flagged_df = _flagged_df(
        spark_session,
        [
            ("E1", False, False, False),
            ("E2", True, False, False),
            ("E3", True, True, False),
            ("E4", False, False, True),
        ],
    )

    metric_df = build_quality_check_metric_dataframe(
        spark=spark_session,
        flagged_df=flagged_df,
        check_cols=CHECK_COLS,
        target_table="datalake_sfmc_clean.send",
        partition_date="2026-08-05",
        env="forno",
        layer="clean",
        metric_name="sfmc_clean_quality_checks",
    )

    rows = _metric_by_check(metric_df)
    assert set(rows) == set(CHECK_COLS)
    assert rows["failed_missing_event_id"]["failed_row_count"] == 2
    assert rows["failed_missing_source_data_extension"]["failed_row_count"] == 1
    assert rows["failed_duplicate_grain"]["failed_row_count"] == 1
    assert all(row["total_row_count"] == 4 for row in rows.values())
    assert all(row["metric_category"] == "quality" for row in rows.values())
    assert all(
        row["source_table"] == "datalake_sfmc_clean.send" for row in rows.values()
    )
    assert all(row["partition_date"] == "2026-08-05" for row in rows.values())
    assert all(row["layer"] == "clean" for row in rows.values())
    assert all(row["environment"] == "forno" for row in rows.values())


def test_build_quality_check_metric_dataframe_emits_zeros_for_a_clean_day(
    spark_session,
):
    """A day where nothing failed still emits a row per check, so a gap in the
    metric means the job did not run, not that it found nothing."""
    flagged_df = _flagged_df(spark_session, [("E1", False, False, False)])

    metric_df = build_quality_check_metric_dataframe(
        spark=spark_session,
        flagged_df=flagged_df,
        check_cols=CHECK_COLS,
        target_table="datalake_sfmc_clean.send",
        partition_date="2026-08-05",
        env="forno",
        layer="clean",
        metric_name="sfmc_clean_quality_checks",
    )

    rows = _metric_by_check(metric_df)
    assert len(rows) == len(CHECK_COLS)
    assert all(row["failed_row_count"] == 0 for row in rows.values())
    assert all(row["total_row_count"] == 1 for row in rows.values())


def test_build_quality_check_metric_dataframe_handles_an_empty_frame(spark_session):
    flagged_df = _flagged_df(spark_session, [])

    metric_df = build_quality_check_metric_dataframe(
        spark=spark_session,
        flagged_df=flagged_df,
        check_cols=CHECK_COLS,
        target_table="datalake_sfmc_clean.send",
        partition_date="2026-08-05",
        env="forno",
        layer="clean",
        metric_name="sfmc_clean_quality_checks",
    )

    rows = _metric_by_check(metric_df)
    assert len(rows) == len(CHECK_COLS)
    assert all(row["failed_row_count"] == 0 for row in rows.values())
    assert all(row["total_row_count"] == 0 for row in rows.values())


def test_save_quality_check_metric_overwrites_the_day_for_that_table(spark_session):
    """The metric write is scoped to (source_table, partition_date) so a rerun
    replaces its counts instead of appending a second set."""
    flagged_df = _flagged_df(spark_session, [("E1", True, False, False)])

    with patch(
        "bietlejuice.base.sst.core.observability.metrics.save_metric_dataframe"
    ) as mock_save:
        save_quality_check_metric(
            spark=spark_session,
            flagged_df=flagged_df,
            check_cols=CHECK_COLS,
            bucket="test-bucket",
            target_table="datalake_sfmc_clean.send",
            partition_date="2026-08-05",
            env="forno",
            layer="clean",
            metric_name="sfmc_clean_quality_checks",
        )

    kwargs = mock_save.call_args.kwargs
    assert kwargs["bucket"] == "test-bucket"
    assert kwargs["metric_table"] == "pipeline_quality_checks"
    assert kwargs["partition_cols"] == ["source_table", "partition_date"]
    assert kwargs["partition_filter_values"] == {
        "source_table": "datalake_sfmc_clean.send",
        "partition_date": "2026-08-05",
    }
    assert kwargs["df"].count() == len(CHECK_COLS)
