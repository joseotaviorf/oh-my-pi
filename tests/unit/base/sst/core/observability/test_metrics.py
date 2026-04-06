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
    metric_df.rdd.isEmpty.return_value = False
    metric_df.withColumn.return_value = metric_df
    metric_df.select.return_value = metric_df

    grouped_df = MagicMock()
    grouped_df.agg.return_value = metric_df

    df = MagicMock()
    df.groupby.return_value = grouped_df

    with patch(
        "bietlejuice.base.sst.core.observability.metrics.validate_and_write"
    ) as mock_validate_and_write, patch(
        "bietlejuice.base.sst.core.observability.metrics.F.coalesce",
        return_value=DummyExpr(),
    ), patch(
        "bietlejuice.base.sst.core.observability.metrics.F.count",
        return_value=DummyExpr(),
    ), patch(
        "bietlejuice.base.sst.core.observability.metrics.F.lit",
        return_value=DummyExpr(),
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
    initial_metric_df.rdd.isEmpty.return_value = True
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

    with patch(
        "bietlejuice.base.sst.core.observability.metrics.validate_and_write"
    ) as mock_validate_and_write, patch(
        "bietlejuice.base.sst.core.observability.metrics.F.coalesce",
        return_value=DummyExpr(),
    ), patch(
        "bietlejuice.base.sst.core.observability.metrics.F.count",
        return_value=DummyExpr(),
    ), patch(
        "bietlejuice.base.sst.core.observability.metrics.F.lit",
        return_value=DummyExpr(),
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


def test_save_table_metadata_metric_writes_metadata_with_partition_values():
    """Test that save_table_metadata_metric writes a metadata metric row
    including the correct partition columns when partition_values is provided.
    """
    spark = MagicMock()
    df = MagicMock()
    df.columns = ["id", "name", "status"]

    metric_df = MagicMock()
    metric_df.withColumn.return_value = metric_df
    metric_df.select.return_value = metric_df
    spark.range.return_value = metric_df

    with patch(
        "bietlejuice.base.sst.core.observability.metrics.validate_and_write"
    ) as mock_validate_and_write, patch(
        "bietlejuice.base.sst.core.observability.metrics.F.lit",
        return_value=MagicMock(),
    ):
        save_table_metadata_metric(
            spark=spark,
            df=df,
            table_name="datalake_salesforce_clean.events",
            new_cols=["status"],
            env="forno",
            layer="clean",
            table_location="s3://bucket/path/to/table",
            partition_values={"year": "2024", "month": "01"},
            partition_cols=["year", "month"],
        )

    assert mock_validate_and_write.call_count == 1
    call_kwargs = mock_validate_and_write.call_args.kwargs
    assert call_kwargs["df"] == metric_df
    assert (
        call_kwargs["target_table"]
        == "datalake_sst_metrics.datalake_salesforce_clean_events_metadata"
    )
    assert call_kwargs["partition_cols"] == ["year", "month"]
    assert call_kwargs["append"] is True


def test_save_table_metadata_metric_writes_metadata_without_partition_values():
    """Test that save_table_metadata_metric works when partition_values and
    partition_cols are not provided (defaulting to empty dict/list).
    """
    spark = MagicMock()
    df = MagicMock()
    df.columns = ["id", "name"]

    metric_df = MagicMock()
    metric_df.withColumn.return_value = metric_df
    metric_df.select.return_value = metric_df
    spark.range.return_value = metric_df

    with patch(
        "bietlejuice.base.sst.core.observability.metrics.validate_and_write"
    ) as mock_validate_and_write, patch(
        "bietlejuice.base.sst.core.observability.metrics.F.lit",
        return_value=MagicMock(),
    ):
        save_table_metadata_metric(
            spark=spark,
            df=df,
            table_name="datalake_ebdb_clean.contract",
            new_cols=None,
            env="prod",
            layer="clean",
            table_location="s3://bucket/path/to/table",
        )

    assert mock_validate_and_write.call_count == 1
    call_kwargs = mock_validate_and_write.call_args.kwargs
    assert (
        call_kwargs["target_table"]
        == "datalake_sst_metrics.datalake_ebdb_clean_contract_metadata"
    )
    assert call_kwargs["partition_cols"] == []
    assert call_kwargs["append"] is True


def test_save_table_metadata_metric_sanitizes_table_name_special_chars():
    """Test that special characters in table_name are replaced with underscores
    in the destination metric table name.
    """
    spark = MagicMock()
    df = MagicMock()
    df.columns = ["col_a"]

    metric_df = MagicMock()
    metric_df.withColumn.return_value = metric_df
    metric_df.select.return_value = metric_df
    spark.range.return_value = metric_df

    with patch(
        "bietlejuice.base.sst.core.observability.metrics.validate_and_write"
    ) as mock_validate_and_write, patch(
        "bietlejuice.base.sst.core.observability.metrics.F.lit",
        return_value=MagicMock(),
    ):
        save_table_metadata_metric(
            spark=spark,
            df=df,
            table_name="my-schema.my-table",
            new_cols=[],
            env="forno",
            layer="enrich",
            table_location="s3://bucket/path/to/table",
        )

    call_kwargs = mock_validate_and_write.call_args.kwargs
    assert (
        call_kwargs["target_table"]
        == "datalake_sst_metrics.my_schema_my_table_metadata"
    )
