from unittest import mock

from bietlejuice.base.sst.core.observability import sensors


@mock.patch.object(sensors, "_table_exists")
def test_partition_has_data_returns_false_when_table_is_missing(
    mock_table_exists,
):
    spark = mock.MagicMock()
    mock_table_exists.return_value = False

    has_data = sensors.partition_has_data(
        spark=spark,
        table_name="datalake_sfmc_raw.tb_sonia_ep2ds",
        partition_date="2026-04-15",
    )

    assert has_data is False
    spark.read.table.assert_not_called()


@mock.patch.object(sensors, "_table_exists")
def test_partition_has_data_returns_false_when_partition_date_column_is_missing(
    mock_table_exists,
):
    spark = mock.MagicMock()
    mock_table_exists.return_value = True
    spark.read.table.return_value.columns = ["external_key"]

    has_data = sensors.partition_has_data(
        spark=spark,
        table_name="datalake_sfmc_raw.tb_sonia_ep2ds",
        partition_date="2026-04-15",
    )

    assert has_data is False


@mock.patch.object(sensors, "_table_exists")
def test_partition_has_data_returns_true_when_date_partition_has_rows(
    mock_table_exists,
):
    spark = mock.MagicMock()
    target_df = mock.MagicMock()
    target_df.columns = ["partition_date"]
    target_df.where.return_value.count.return_value = 2
    spark.read.table.return_value = target_df
    mock_table_exists.return_value = True

    has_data = sensors.partition_has_data(
        spark=spark,
        table_name="datalake_sfmc_raw.tb_sonia_ep2ds",
        partition_date="2026-04-15",
    )

    assert has_data is True


@mock.patch.object(sensors, "_table_exists")
def test_partition_has_data_filters_by_hour_when_provided(
    mock_table_exists,
):
    spark = mock.MagicMock()
    target_df = mock.MagicMock()
    target_df.columns = ["partition_date", "partition_hour"]
    filtered_by_date = mock.MagicMock()
    filtered_by_date_and_hour = mock.MagicMock()
    filtered_by_date_and_hour.count.return_value = 5
    target_df.where.return_value = filtered_by_date
    filtered_by_date.where.return_value = filtered_by_date_and_hour
    spark.read.table.return_value = target_df
    mock_table_exists.return_value = True

    has_data = sensors.partition_has_data(
        spark=spark,
        table_name="datalake_sf_cdc_raw.tb_account",
        partition_date="2026-04-15",
        partition_hour="10",
    )

    assert has_data is True
    assert target_df.where.call_count == 1
    assert filtered_by_date.where.call_count == 1


@mock.patch.object(sensors, "_table_exists")
def test_partition_has_data_returns_false_when_partition_hour_column_is_missing(
    mock_table_exists,
):
    spark = mock.MagicMock()
    target_df = mock.MagicMock()
    target_df.columns = ["partition_date"]
    spark.read.table.return_value = target_df
    mock_table_exists.return_value = True

    has_data = sensors.partition_has_data(
        spark=spark,
        table_name="datalake_sf_cdc_raw.tb_account",
        partition_date="2026-04-15",
        partition_hour="10",
    )

    assert has_data is False
