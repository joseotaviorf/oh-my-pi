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

    @pytest.mark.parametrize(
        "base_path",
        [
            "s3://bucket/table/",
            "s3://bucket/table///",
        ],
    )
    def test_load_normalizes_trailing_slashes_on_base_path(
        self, spark_reader, ls_entry, base_path
    ):
        mock_dbutils = mock.Mock()
        mock_dbutils.fs.ls.return_value = [ls_entry]
        reader = DateRangePartitionReader(spark_reader, mock_dbutils)
        spark_reader.load.return_value = "data"

        reader.load(base_path, datetime(2024, 1, 1), datetime(2024, 1, 1), "json")

        mock_dbutils.fs.ls.assert_called_once_with(
            "s3://bucket/table/year=2024/month=01/day=01"
        )
        spark_reader.option.assert_called_once_with("basePath", "s3://bucket/table")
        spark_reader.load.assert_called_once_with(
            ["s3://bucket/table/year=2024/month=01/day=01"],
            format="json",
        )

    def test_load_file_not_found_error_uses_normalized_base_path(self, spark_reader):
        mock_dbutils = mock.Mock()
        mock_dbutils.fs.ls.side_effect = Exception("java.io.FileNotFoundException")
        reader = DateRangePartitionReader(spark_reader, mock_dbutils)

        with pytest.raises(
            FileNotFoundError,
            match=r"No data found in s3://bucket/table for the given date range",
        ):
            reader.load(
                "s3://bucket/table/",
                datetime(2024, 1, 1),
                datetime(2024, 1, 1),
                "json",
            )

    def test_find_existing_paths_does_not_strip_base_path(self, spark_reader, ls_entry):
        """Normalization is owned by load(); the helper joins paths as given."""
        mock_dbutils = mock.Mock()
        mock_dbutils.fs.ls.return_value = [ls_entry]
        reader = DateRangePartitionReader(spark_reader, mock_dbutils)

        paths = reader._find_existing_paths(
            "s3://bucket/table/",
            datetime(2024, 1, 1),
            datetime(2024, 1, 1),
        )

        mock_dbutils.fs.ls.assert_called_once_with(
            "s3://bucket/table//year=2024/month=01/day=01"
        )
        assert paths == ["s3://bucket/table//year=2024/month=01/day=01"]

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
