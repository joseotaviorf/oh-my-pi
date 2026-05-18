from datetime import datetime
from unittest import mock

import pytest

from bietlejuice.base.cdc.reader.date_range_partition_reader import (
    DateRangePartitionReader,
)


class TestDateRangePartitionReader:
    @pytest.fixture
    def spark_reader(self):
        reader = mock.Mock()
        reader.option.return_value = reader
        return reader

    @pytest.fixture
    def ls_entry(self):
        return mock.MagicMock(name="fs_list_entry")

    def test_load_should_raise_error_if_no_data_found(self, spark_reader):
        mock_dbutils = mock.Mock()
        mock_dbutils.fs.ls.side_effect = Exception("java.io.FileNotFoundException")
        reader = DateRangePartitionReader(spark_reader, mock_dbutils)

        with pytest.raises(FileNotFoundError):
            reader.load(
                "base_path", datetime(2024, 1, 1), datetime(2024, 1, 1), "format"
            )
        reader.dbutils.fs.ls.assert_called_once_with(
            "base_path/year=2024/month=01/day=01"
        )
        spark_reader.load.assert_not_called()

    def test_load_skips_day_when_ls_returns_empty_list(self, spark_reader):
        mock_dbutils = mock.Mock()
        mock_dbutils.fs.ls.return_value = []
        reader = DateRangePartitionReader(spark_reader, mock_dbutils)

        with pytest.raises(FileNotFoundError):
            reader.load(
                "base_path", datetime(2024, 1, 1), datetime(2024, 1, 1), "format"
            )
        reader.dbutils.fs.ls.assert_called_once_with(
            "base_path/year=2024/month=01/day=01"
        )
        spark_reader.load.assert_not_called()

    def test_load_includes_only_days_with_nonempty_ls(self, spark_reader, ls_entry):
        mock_dbutils = mock.Mock()

        def ls_side_effect(path):
            if path.endswith("day=01"):
                return []
            if path.endswith("day=02"):
                return [ls_entry]
            return []

        mock_dbutils.fs.ls.side_effect = ls_side_effect
        reader = DateRangePartitionReader(spark_reader, mock_dbutils)
        spark_reader.load.return_value = "data"

        result = reader.load(
            "base_path", datetime(2024, 1, 1), datetime(2024, 1, 2), "format"
        )

        assert result == "data"
        spark_reader.load.assert_called_once_with(
            ["base_path/year=2024/month=01/day=02"],
            format="format",
        )

    def test_load_should_return_data_if_found(self, spark_reader, ls_entry):
        mock_dbutils = mock.Mock()
        mock_dbutils.fs.ls.return_value = [ls_entry]
        reader = DateRangePartitionReader(spark_reader, mock_dbutils)
        spark_reader.load.return_value = "data"

        result = reader.load(
            "base_path", datetime(2024, 1, 1), datetime(2024, 1, 5), "format"
        )

        assert result == "data"
        spark_reader.option.assert_called_once_with("basePath", "base_path")
        spark_reader.load.assert_called_once_with(
            [
                "base_path/year=2024/month=01/day=01",
                "base_path/year=2024/month=01/day=02",
                "base_path/year=2024/month=01/day=03",
                "base_path/year=2024/month=01/day=04",
                "base_path/year=2024/month=01/day=05",
            ],
            format="format",
        )

    def test_load_should_apply_custom_partition_format(self, spark_reader, ls_entry):
        mock_dbutils = mock.Mock()
        mock_dbutils.fs.ls.return_value = [ls_entry]
        reader = DateRangePartitionReader(
            spark_reader, mock_dbutils, partition_format="year=%Y/month=%-m/day=%-d"
        )
        spark_reader.load.return_value = "data"

        result = reader.load(
            "base_path", datetime(2024, 1, 1), datetime(2024, 1, 5), "format"
        )

        assert result == "data"
        spark_reader.option.assert_called_once_with("basePath", "base_path")
        spark_reader.load.assert_called_once_with(
            [
                "base_path/year=2024/month=1/day=1",
                "base_path/year=2024/month=1/day=2",
                "base_path/year=2024/month=1/day=3",
                "base_path/year=2024/month=1/day=4",
                "base_path/year=2024/month=1/day=5",
            ],
            format="format",
        )
