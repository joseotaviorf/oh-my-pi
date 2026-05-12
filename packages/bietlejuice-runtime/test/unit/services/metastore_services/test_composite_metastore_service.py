from unittest import mock
from unittest.mock import MagicMock, Mock

import pytest

from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.metastore_services.composite_metastore_service import (
    CompositeMetastoreService,
)


class TestCompositeMetastoreServiceSparkDelegation:
    def test_refresh_table_delegates_to_primary_only(self):
        primary = SparkMetastoreService(Mock())
        secondary = MagicMock()
        composite = CompositeMetastoreService([primary, secondary])

        with mock.patch.object(primary, "refresh_table") as mock_refresh:
            composite.refresh_table("mydb", "mytable")
            mock_refresh.assert_called_once_with("mydb", "mytable")

    def test_get_table_schema_delegates_to_primary(self):
        primary = SparkMetastoreService(Mock())
        secondary = MagicMock()
        composite = CompositeMetastoreService([primary, secondary])

        with mock.patch.object(
            primary, "get_table_schema", return_value={"a": "int"}
        ) as mock_gs:
            result = composite.get_table_schema("db", "tbl", ignore_partition_keys=True)

        assert result == {"a": "int"}
        mock_gs.assert_called_once_with("db", "tbl", True)

    def test_merge_table_and_dataframe_schemas_delegates_to_primary(self):
        primary = SparkMetastoreService(Mock())
        secondary = MagicMock()
        composite = CompositeMetastoreService([primary, secondary])
        df = Mock()

        with mock.patch.object(
            primary,
            "merge_table_and_dataframe_schemas",
            return_value={"merged": True},
        ) as mock_merge:
            result = composite.merge_table_and_dataframe_schemas("db", "tbl", df)

        assert result == {"merged": True}
        mock_merge.assert_called_once_with("db", "tbl", df)

    def test_spark_primary_raises_when_primary_not_spark(self):
        not_spark = MagicMock()
        composite = CompositeMetastoreService([not_spark])

        with pytest.raises(TypeError, match="SparkMetastoreService"):
            composite.refresh_table("db", "tbl")
