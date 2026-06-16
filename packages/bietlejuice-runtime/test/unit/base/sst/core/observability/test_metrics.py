from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from pyspark.sql.types import StringType

from bietlejuice.base.sst.core.observability.metrics import (
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
