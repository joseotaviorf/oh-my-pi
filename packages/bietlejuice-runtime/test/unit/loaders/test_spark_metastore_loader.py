from collections import OrderedDict
from unittest.mock import Mock, patch

import pytest
from pyspark.sql.types import StringType, StructField, StructType

from bietlejuice.services.schema_service import SchemaService


class TestSparkMetastoreLoader:
    @pytest.fixture(autouse=True)
    def unity_catalog_helper(self):
        with patch(
            "bietlejuice.base.spark.unity_catalog_helper.UnityCatalogHelper"
        ) as unity_catalog_helper:
            yield unity_catalog_helper

    @pytest.mark.parametrize(
        "format_options, mode, database_name, table_name, database_location",
        [
            ("parquet", "append", "", "test", "local/path"),
            ("csv", "overwrite", "house", "real", "s3://path"),
        ],
    )
    @patch.object(SchemaService, "get_schema_from_dataframe")
    def test_update_metastore(
        self,
        mocked_schema_service,
        format_options,
        mode,
        database_name,
        table_name,
        database_location,
        mocked_write_df,
        metastore_loader,
    ):
        # given
        s3_path = database_location + table_name
        partitions = []
        df_schema = OrderedDict({"col": "string"})

        mocked_schema_service.return_value = df_schema
        metastore_loader.schema_service.get_schema_from_dataframe = (
            mocked_schema_service
        )

        # when
        metastore_loader.update_metastore(
            df=mocked_write_df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
        )

        # then
        metastore_loader.metastore_service.create_external_table.assert_called_with(
            database_name, table_name, s3_path, df_schema, partitions, format_options
        )

    @pytest.mark.parametrize(
        "database_name, table_name, format_options, database_location",
        [
            (None, "table", None, None),
            ("database", None, None, None),
            ("database", 123, None, None),
        ],
    )
    def test_update_metastore_with_invalid_params(
        self,
        database_name,
        table_name,
        format_options,
        database_location,
        mocked_write_df,
        metastore_loader,
    ):
        # act and assert
        with pytest.raises(ValueError):
            metastore_loader.update_metastore(
                mocked_write_df,
                database_name,
                table_name,
                format_options,
                database_location,
            )

    def test_update_metastore_with_invalid_df(self, metastore_loader):
        # arrange
        database_name = "default"
        table_name = "test_table"
        format_options = "overwrite"
        database_location = "path/to/file"

        df = None

        with pytest.raises(ValueError):
            metastore_loader.update_metastore(
                df=df,
                database_name=database_name,
                table_name=table_name,
                format_options=format_options,
                database_location=database_location,
            )

    @pytest.mark.parametrize(
        "format_options, mode, database_name, table_name, database_location",
        [
            ("parquet", "append", "", "test", "local/path"),
            ("csv", "overwrite", "house", "real", "s3://path"),
        ],
    )
    @patch.object(SchemaService, "get_schema_from_dataframe")
    def test_update_metastore_should_not_sync_if_uc_is_not_enabled(
        self,
        mocked_schema_service,
        format_options,
        mode,
        database_name,
        table_name,
        database_location,
        mocked_write_df,
        metastore_loader,
        unity_catalog_helper,
    ):
        # given
        df_schema = OrderedDict({"col": "string"})

        mocked_schema_service.return_value = df_schema
        metastore_loader.schema_service.get_schema_from_dataframe = (
            mocked_schema_service
        )
        unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = False
        unity_catalog_helper.is_default_catalog_using_unity.return_value = False

        # when
        metastore_loader.update_metastore(
            df=mocked_write_df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
        )

        # then
        unity_catalog_helper.sync_table_to_unity_catalog.assert_not_called()

    @pytest.mark.parametrize(
        "format_options, mode, database_name, table_name, database_location",
        [
            ("parquet", "append", "", "test", "local/path"),
            ("csv", "overwrite", "house", "real", "s3://path"),
        ],
    )
    @patch.object(SchemaService, "get_schema_from_dataframe")
    def test_update_metastore_should_not_sync_if_uc_is_enabled_but_table_is_saved_directly_to_uc(
        self,
        mocked_schema_service,
        format_options,
        mode,
        database_name,
        table_name,
        database_location,
        mocked_write_df,
        metastore_loader,
        unity_catalog_helper,
    ):
        # given
        df_schema = OrderedDict({"col": "string"})

        mocked_schema_service.return_value = df_schema
        metastore_loader.schema_service.get_schema_from_dataframe = (
            mocked_schema_service
        )
        unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = True
        unity_catalog_helper.is_default_catalog_using_unity.return_value = True

        # when
        metastore_loader.update_metastore(
            df=mocked_write_df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
        )

        # then
        unity_catalog_helper.sync_table_to_unity_catalog.assert_not_called()

    @pytest.mark.parametrize(
        "format_options, mode, database_name, table_name, database_location",
        [
            ("parquet", "append", "", "test", "local/path"),
            ("csv", "overwrite", "house", "real", "s3://path"),
        ],
    )
    @patch.object(SchemaService, "get_schema_from_dataframe")
    def test_update_metastore_should_not_sync_if_uc_enabled_but_partitioned(
        self,
        mocked_schema_service,
        format_options,
        mode,
        database_name,
        table_name,
        database_location,
        mocked_write_df,
        metastore_loader,
        unity_catalog_helper,
    ):
        # given
        df_schema = OrderedDict({"col": "string"})

        mocked_schema_service.return_value = df_schema
        metastore_loader.schema_service.get_schema_from_dataframe = (
            mocked_schema_service
        )
        unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = True
        unity_catalog_helper.is_default_catalog_using_unity.return_value = False

        # when
        metastore_loader.update_metastore(
            df=mocked_write_df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
            partitions=["year", "month", "day"],
        )

        # then
        unity_catalog_helper.sync_table_to_unity_catalog.assert_not_called()

    @pytest.mark.parametrize(
        "format_options, mode, database_name, table_name, database_location",
        [
            ("parquet", "append", "", "test", "local/path"),
            ("csv", "overwrite", "house", "real", "s3://path"),
        ],
    )
    @patch.object(SchemaService, "get_schema_from_dataframe")
    def test_update_metastore_should_sync_if_uc_enabled_and_table_is_not_partitioned(
        self,
        mocked_schema_service,
        format_options,
        mode,
        database_name,
        table_name,
        database_location,
        mocked_write_df,
        metastore_loader,
        unity_catalog_helper,
    ):
        # given
        df_schema = OrderedDict({"col": "string"})

        mocked_schema_service.return_value = df_schema
        metastore_loader.schema_service.get_schema_from_dataframe = (
            mocked_schema_service
        )
        unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = True
        unity_catalog_helper.is_default_catalog_using_unity.return_value = False

        # when
        metastore_loader.update_metastore(
            df=mocked_write_df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
        )

        # then
        unity_catalog_helper.sync_table_to_unity_catalog.assert_called_once_with(
            f"{database_name}.{table_name}"
        )


class TestCreateMergeSchemaDoesNotRecreateOnCasingAlone:
    """``create_merge_schema`` is what gates the drop-and-recreate.

    ``recreate_table`` drops the table before creating it, so a spurious
    non-``None`` return is destructive. These tests wire a real
    ``SparkMetastoreService`` rather than a mocked merge so they exercise the
    actual interaction between the two.
    """

    @staticmethod
    def _loader(table_schema, table_name="t"):
        from bietlejuice.loaders.spark_metastore_loader import SparkMetastoreLoader
        from bietlejuice.services.metastore_services import SparkMetastoreService

        service = SparkMetastoreService(Mock())
        service.get_table_names = Mock(return_value=[table_name])
        service.get_table_schema = Mock(return_value=table_schema)
        return SparkMetastoreLoader(service)

    @staticmethod
    def _df(*columns):
        return Mock(
            schema=StructType([StructField(name, StringType()) for name in columns])
        )

    def test_returns_none_when_casing_matches_databricks(self):
        """Databricks: HMS preserves the df's casing, so nothing may be recreated."""
        loader = self._loader(
            OrderedDict([("Id", "string"), ("BusinessProcessId", "string")])
        )

        result = loader.create_merge_schema(
            "db", "t", self._df("Id", "BusinessProcessId")
        )

        assert result is None

    def test_returns_none_when_only_casing_differs_emr(self):
        """EMR: Glue lower-cased the table; a casing delta alone must not recreate."""
        loader = self._loader(
            OrderedDict([("id", "string"), ("businessprocessid", "string")])
        )

        result = loader.create_merge_schema(
            "db", "t", self._df("Id", "BusinessProcessId")
        )

        assert result is None

    def test_returns_schema_when_a_column_is_genuinely_new(self):
        loader = self._loader(OrderedDict([("id", "string")]))

        result = loader.create_merge_schema("db", "t", self._df("id", "brand_new"))

        assert result == OrderedDict([("id", "string"), ("brand_new", "string")])
