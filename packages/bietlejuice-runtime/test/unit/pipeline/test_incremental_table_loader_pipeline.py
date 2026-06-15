from unittest import mock

import pytest

from bietlejuice.pipeline.incremental_table_loader_pipeline import (
    IncrementalTableLoaderPipeline,
)


class TestIncrementalTableLoaderPipeline:
    @pytest.fixture(autouse=True)
    def mock_s3_loader(self):
        with mock.patch(
            "bietlejuice.pipeline.incremental_table_loader_pipeline.S3Loader"
        ) as s3_loader:
            yield s3_loader

    @pytest.fixture(autouse=True)
    def mock_metastore_service(self):
        with mock.patch(
            "bietlejuice.pipeline.incremental_table_loader_pipeline.MetastoreServiceFactory.create_loader_metastore_service",
            return_value=mock.MagicMock(),
        ) as factory_mock:
            yield factory_mock.return_value

    @pytest.fixture(autouse=True)
    def mock_spark_metastore_loader(self):
        with mock.patch(
            "bietlejuice.pipeline.incremental_table_loader_pipeline.SparkMetastoreLoader"
        ) as spark_metastore_loader:
            yield spark_metastore_loader

    @pytest.fixture(autouse=True)
    def mock_unity_catalog_helper(self):
        with mock.patch(
            "bietlejuice.pipeline.incremental_table_loader_pipeline.UnityCatalogHelper"
        ) as unity_catalog_helper:
            unity_catalog_helper.is_default_catalog_using_unity.return_value = False
            unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = False
            yield unity_catalog_helper

    def _pipeline(self, partitions=None):
        return IncrementalTableLoaderPipeline(
            database_name="db",
            table_name="table",
            database_location="s3://bucket/db/",
            layer="clean",
            query="query",
            partitions=partitions or [],
            target_database_name="target_db",
            target_database_location="s3://bucket/target/",
        )

    def test_uc_parquet_with_partitions_registers_partitions_after_save_as_table(
        self,
        mock_metastore_service,
        mock_unity_catalog_helper,
        mock_spark_metastore_loader,
    ):
        mock_unity_catalog_helper.is_default_catalog_using_unity.return_value = True
        df = mock.MagicMock()
        pipeline = self._pipeline(partitions=["year", "month", "day"])

        pipeline.load_and_register(df, "PARQUET")

        mock_spark_metastore_loader.return_value.update_metastore.assert_not_called()
        mock_metastore_service.create_new_partitions_from_df.assert_called_once_with(
            df=df,
            database_name="target_db",
            table_name="table",
            partition_cols=["year", "month", "day"],
        )

    def test_uc_json_with_partitions_registers_partitions(
        self, mock_metastore_service, mock_unity_catalog_helper
    ):
        mock_unity_catalog_helper.is_default_catalog_using_unity.return_value = True
        df = mock.MagicMock()
        pipeline = self._pipeline(partitions=["year", "month", "day"])

        pipeline.load_and_register(df, "JSON")

        mock_metastore_service.create_new_partitions_from_df.assert_called_once_with(
            df=df,
            database_name="target_db",
            table_name="table",
            partition_cols=["year", "month", "day"],
        )

    def test_delta_skips_glue_partition_registration(
        self, mock_metastore_service, mock_unity_catalog_helper
    ):
        mock_unity_catalog_helper.is_default_catalog_using_unity.return_value = True
        pipeline = self._pipeline(partitions=["year", "month", "day"])

        pipeline.load_and_register(mock.MagicMock(), "DELTA")

        mock_metastore_service.create_new_partitions_from_df.assert_not_called()

    def test_uc_parquet_without_partitions_skips_partition_registration(
        self, mock_metastore_service, mock_unity_catalog_helper
    ):
        mock_unity_catalog_helper.is_default_catalog_using_unity.return_value = True

        self._pipeline(partitions=[]).load_and_register(mock.MagicMock(), "PARQUET")

        mock_metastore_service.create_new_partitions_from_df.assert_not_called()

    def test_non_uc_parquet_still_registers_partitions(
        self,
        mock_metastore_service,
        mock_unity_catalog_helper,
        mock_spark_metastore_loader,
    ):
        mock_unity_catalog_helper.is_default_catalog_using_unity.return_value = False
        df = mock.MagicMock()
        pipeline = self._pipeline(partitions=["year", "month", "day"])

        pipeline.load_and_register(df, "PARQUET")

        mock_spark_metastore_loader.return_value.update_metastore.assert_called_once()
        mock_metastore_service.create_new_partitions_from_df.assert_called_once_with(
            df=df,
            database_name="target_db",
            table_name="table",
            partition_cols=["year", "month", "day"],
        )

    @mock.patch(
        "bietlejuice.services.schema_service.SchemaService.get_schema_from_dataframe"
    )
    @mock.patch(
        "bietlejuice.base.spark.catalog_strategy_resolver.CatalogStrategyResolver"
    )
    def test_uc_parquet_incremental_ensures_glue_table_before_registering_partition(
        self,
        mock_resolver,
        mock_get_schema,
        mock_metastore_service,
        mock_unity_catalog_helper,
    ):
        # User's scenario: an incremental UC parquet write of a new day partition
        # must ensure the Glue table exists, then register the new partition.
        mock_unity_catalog_helper.is_default_catalog_using_unity.return_value = True
        mock_get_schema.return_value = {"id": "bigint"}
        df = mock.MagicMock()
        pipeline = self._pipeline(partitions=["year", "month", "day"])

        manager = mock.Mock()
        manager.attach_mock(mock_resolver.sync_to_secondary_catalog, "sync")
        manager.attach_mock(
            mock_metastore_service.create_new_partitions_from_df, "register"
        )

        pipeline.load_and_register(df, "PARQUET")

        mock_resolver.sync_to_secondary_catalog.assert_called_once_with(
            database_name="target_db",
            table_name="table",
            table_location="s3://bucket/target/table",
            table_schema={"id": "bigint"},
            partitions=["year", "month", "day"],
            format_str="PARQUET",
        )
        call_names = [name for name, _, _ in manager.mock_calls]
        assert call_names.index("sync") < call_names.index("register")

    @mock.patch(
        "bietlejuice.base.spark.catalog_strategy_resolver.CatalogStrategyResolver"
    )
    def test_delta_does_not_ensure_glue_table_via_helper(
        self, mock_resolver, mock_unity_catalog_helper
    ):
        mock_unity_catalog_helper.is_default_catalog_using_unity.return_value = True
        pipeline = self._pipeline(partitions=["year", "month", "day"])

        pipeline.load_and_register(mock.MagicMock(), "DELTA")

        mock_resolver.sync_to_secondary_catalog.assert_not_called()
