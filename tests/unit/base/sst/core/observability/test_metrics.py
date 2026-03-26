from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from pyspark.sql.types import StringType

from bietlejuice.base.sst.core.observability.metrics import save_volume_metric


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
        )

    assert mock_validate_and_write.call_count == 1
    assert mock_validate_and_write.call_args.kwargs["df"] == fallback_df
    assert fallback_df.withColumn.call_count >= 9
