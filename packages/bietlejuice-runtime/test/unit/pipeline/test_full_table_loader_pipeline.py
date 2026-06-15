from unittest import mock

import pytest

from bietlejuice.pipeline.full_table_loader_pipeline import FullTableLoaderPipeline


class TestFullTableLoaderPipeline:
    @pytest.fixture(autouse=True)
    def mock_s3_loader(self):
        with mock.patch(
            "bietlejuice.pipeline.full_table_loader_pipeline.S3Loader"
        ) as s3_loader:
            yield s3_loader

    @pytest.fixture(autouse=True)
    def mock_loader_metastore_service(self):
        with mock.patch(
            "bietlejuice.pipeline.full_table_loader_pipeline.MetastoreServiceFactory.create_loader_metastore_service",
            return_value=mock.MagicMock(),
        ) as factory_mock:
            yield factory_mock.return_value

    @pytest.fixture(autouse=True)
    def mock_spark_metastore_loader(self):
        with mock.patch(
            "bietlejuice.pipeline.full_table_loader_pipeline.SparkMetastoreLoader"
        ) as spark_metastore_loader:
            yield spark_metastore_loader

    @pytest.fixture(autouse=True)
    def mock_base_spark_context(self):
        with mock.patch(
            "bietlejuice.pipeline.full_table_loader_pipeline.BaseSparkContext"
        ) as base_spark_context:
            base_spark_context.spark.version = "3.3.0"
            yield base_spark_context

    @pytest.fixture(autouse=True)
    def mock_unity_catalog_helper(self):
        with mock.patch(
            "bietlejuice.pipeline.full_table_loader_pipeline.UnityCatalogHelper"
        ) as unity_catalog_helper:
            unity_catalog_helper.is_default_catalog_using_unity.return_value = False
            yield unity_catalog_helper

    def test_load_and_register_should_optimize_when_spark_version_is_below_3_3(
        self, mock_s3_loader, mock_base_spark_context
    ):
        # arrange
        pipeline = FullTableLoaderPipeline(
            database_name="db",
            table_name="table",
            database_location="s3://bucket/db",
            layer="layer",
            query="query",
            partitions=[],
        )
        mock_base_spark_context.spark.version = "3.2.0"

        # act
        pipeline.load_and_register(
            df=mock.MagicMock(), format_options={"format": "parquet"}
        )

        # assert
        mock_s3_loader.return_value.load_df.assert_called_once_with(
            df=mock.ANY,
            format_options={"format": "parquet"},
            s3_path="s3://bucket/dbtable",
            partitions=[],
            optimize_dataframe=True,
        )

    def test_load_and_register_should_optimize_when_table_is_partitioned(
        self, mock_s3_loader, mock_base_spark_context
    ):
        # arrange
        pipeline = FullTableLoaderPipeline(
            database_name="db",
            table_name="table",
            database_location="s3://bucket/db",
            layer="layer",
            query="query",
            partitions=["col1"],
        )
        mock_base_spark_context.spark.version = "3.3.0"

        # act
        pipeline.load_and_register(
            df=mock.MagicMock(), format_options={"format": "parquet"}
        )

        # assert
        mock_s3_loader.return_value.load_df.assert_called_once_with(
            df=mock.ANY,
            format_options={"format": "parquet"},
            s3_path="s3://bucket/dbtable",
            partitions=["col1"],
            optimize_dataframe=True,
        )

    def test_load_and_register_should_not_optimize_when_spark_version_is_above_3_3_and_table_is_not_partitioned(
        self, mock_s3_loader, mock_base_spark_context
    ):
        # arrange
        pipeline = FullTableLoaderPipeline(
            database_name="db",
            table_name="table",
            database_location="s3://bucket/db",
            layer="layer",
            query="query",
            partitions=[],
        )
        mock_base_spark_context.spark.version = "3.3.0"

        # act
        pipeline.load_and_register(
            df=mock.MagicMock(), format_options={"format": "parquet"}
        )

        # assert
        mock_s3_loader.return_value.load_df.assert_called_once_with(
            df=mock.ANY,
            format_options={"format": "parquet"},
            s3_path="s3://bucket/dbtable",
            partitions=[],
            optimize_dataframe=False,
        )

    def test_load_and_register_should_optimize_when_flag_is_true(
        self, mock_s3_loader, mock_base_spark_context
    ):
        # arrange
        pipeline = FullTableLoaderPipeline(
            database_name="db",
            table_name="table",
            database_location="s3://bucket/db",
            layer="layer",
            query="query",
            partitions=[],
        )
        mock_base_spark_context.spark.version = "3.3.0"

        # act
        pipeline.load_and_register(
            df=mock.MagicMock(),
            format_options={"format": "parquet"},
            optimize_dataframe=True,
        )

        # assert
        mock_s3_loader.return_value.load_df.assert_called_once_with(
            df=mock.ANY,
            format_options={"format": "parquet"},
            s3_path="s3://bucket/dbtable",
            partitions=[],
            optimize_dataframe=True,
        )

    def test_load_and_register_should_pass_table_name_when_uc_enabled(
        self, mock_s3_loader, mock_base_spark_context, mock_unity_catalog_helper
    ):
        # arrange
        pipeline = FullTableLoaderPipeline(
            database_name="db",
            table_name="table",
            database_location="s3://bucket/db",
            layer="layer",
            query="query",
            partitions=[],
        )
        mock_base_spark_context.spark.version = "3.3.0"
        mock_unity_catalog_helper.is_default_catalog_using_unity.return_value = True

        # act
        pipeline.load_and_register(
            df=mock.MagicMock(),
            format_options={"format": "parquet"},
            optimize_dataframe=True,
        )

        # assert
        mock_s3_loader.return_value.load_df.assert_called_once_with(
            df=mock.ANY,
            format_options={"format": "parquet"},
            s3_path="s3://bucket/dbtable",
            partitions=[],
            optimize_dataframe=True,
            full_table_name="db.table",
        )

    def test_load_and_register_should_not_apply_privileges_if_uc_disabled(
        self, mock_base_spark_context, mock_unity_catalog_helper
    ):
        privileges = mock.MagicMock()
        # arrange
        pipeline = FullTableLoaderPipeline(
            database_name="db",
            table_name="table",
            database_location="s3://bucket/db",
            layer="layer",
            query="query",
            partitions=[],
            table_privileges=privileges,
        )
        mock_base_spark_context.spark.version = "3.3.0"
        mock_unity_catalog_helper.is_default_catalog_using_unity.return_value = False
        mock_unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = False

        # act
        pipeline.load_and_register(
            df=mock.MagicMock(),
            format_options={"format": "parquet"},
            optimize_dataframe=True,
        )

        # assert
        privileges.apply.assert_not_called()

    def test_load_and_register_should_apply_privileges_if_uc_enabled(
        self, mock_base_spark_context, mock_unity_catalog_helper
    ):
        privileges = mock.MagicMock()
        # arrange
        pipeline = FullTableLoaderPipeline(
            database_name="db",
            table_name="table",
            database_location="s3://bucket/db",
            layer="layer",
            query="query",
            partitions=[],
            table_privileges=privileges,
        )
        mock_base_spark_context.spark.version = "3.3.0"
        mock_unity_catalog_helper.is_default_catalog_using_unity.return_value = False
        mock_unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = True

        # act
        pipeline.load_and_register(
            df=mock.MagicMock(),
            format_options={"format": "parquet"},
            optimize_dataframe=True,
        )

        # assert
        privileges.apply.assert_called_once_with()

    def test_load_and_register_uc_partitioned_table_registers_partitions_from_df(
        self,
        mock_loader_metastore_service,
        mock_unity_catalog_helper,
        mock_spark_metastore_loader,
    ):
        mock_unity_catalog_helper.is_default_catalog_using_unity.return_value = True
        df = mock.MagicMock()
        pipeline = FullTableLoaderPipeline(
            database_name="db",
            table_name="table",
            database_location="s3://bucket/db",
            layer="layer",
            query="query",
            partitions=["year", "month", "day"],
        )

        pipeline.load_and_register(df, format_options="PARQUET")

        mock_spark_metastore_loader.return_value.update_metastore.assert_not_called()
        mock_loader_metastore_service.create_new_partitions_from_df.assert_called_once_with(
            df=df,
            database_name="db",
            table_name="table",
            partition_cols=["year", "month", "day"],
        )

    def test_load_and_register_uc_partitioned_delta_skips_partition_registration(
        self, mock_loader_metastore_service, mock_unity_catalog_helper
    ):
        mock_unity_catalog_helper.is_default_catalog_using_unity.return_value = True
        pipeline = FullTableLoaderPipeline(
            database_name="db",
            table_name="table",
            database_location="s3://bucket/db",
            layer="layer",
            query="query",
            partitions=["year", "month", "day"],
        )

        pipeline.load_and_register(mock.MagicMock(), format_options="DELTA")

        mock_loader_metastore_service.create_new_partitions_from_df.assert_not_called()

    @mock.patch(
        "bietlejuice.services.schema_service.SchemaService.get_schema_from_dataframe"
    )
    @mock.patch(
        "bietlejuice.base.spark.catalog_strategy_resolver.CatalogStrategyResolver"
    )
    def test_load_and_register_uc_partitioned_parquet_ensures_glue_table_before_partitions(
        self,
        mock_resolver,
        mock_get_schema,
        mock_loader_metastore_service,
        mock_unity_catalog_helper,
        mock_spark_metastore_loader,
    ):
        mock_unity_catalog_helper.is_default_catalog_using_unity.return_value = True
        mock_get_schema.return_value = {"id": "bigint"}
        df = mock.MagicMock()
        pipeline = FullTableLoaderPipeline(
            database_name="db",
            table_name="table",
            database_location="s3://bucket/db",
            layer="layer",
            query="query",
            partitions=["year", "month", "day"],
        )

        # Order tracker: the Glue table must be ensured before partitions register.
        manager = mock.Mock()
        manager.attach_mock(mock_resolver.sync_to_secondary_catalog, "sync")
        manager.attach_mock(
            mock_loader_metastore_service.create_new_partitions_from_df, "register"
        )

        pipeline.load_and_register(df, format_options="PARQUET")

        mock_resolver.sync_to_secondary_catalog.assert_called_once_with(
            database_name="db",
            table_name="table",
            table_location="s3://bucket/dbtable",
            table_schema={"id": "bigint"},
            partitions=["year", "month", "day"],
            format_str="PARQUET",
        )
        call_names = [name for name, _, _ in manager.mock_calls]
        assert call_names.index("sync") < call_names.index("register")

    @mock.patch(
        "bietlejuice.services.schema_service.SchemaService.get_schema_from_dataframe"
    )
    @mock.patch(
        "bietlejuice.base.spark.catalog_strategy_resolver.CatalogStrategyResolver"
    )
    def test_load_and_register_uc_non_partitioned_parquet_still_ensures_glue_table(
        self,
        mock_resolver,
        mock_get_schema,
        mock_loader_metastore_service,
        mock_unity_catalog_helper,
    ):
        mock_unity_catalog_helper.is_default_catalog_using_unity.return_value = True
        mock_get_schema.return_value = {"id": "bigint"}
        pipeline = FullTableLoaderPipeline(
            database_name="db",
            table_name="table",
            database_location="s3://bucket/db",
            layer="layer",
            query="query",
            partitions=[],
        )

        pipeline.load_and_register(mock.MagicMock(), format_options="PARQUET")

        # Table is ensured in Glue even with no partitions ...
        mock_resolver.sync_to_secondary_catalog.assert_called_once()
        # ... but there are no partitions to register.
        mock_loader_metastore_service.create_new_partitions_from_df.assert_not_called()

    @mock.patch(
        "bietlejuice.base.spark.catalog_strategy_resolver.CatalogStrategyResolver"
    )
    def test_load_and_register_delta_does_not_ensure_glue_table_via_helper(
        self, mock_resolver, mock_unity_catalog_helper
    ):
        # The parquet/json helper is a no-op for Delta (Delta keeps metadata
        # externally; DeltaTableLoaderPipeline handles its own secondary sync).
        mock_unity_catalog_helper.is_default_catalog_using_unity.return_value = True
        pipeline = FullTableLoaderPipeline(
            database_name="db",
            table_name="table",
            database_location="s3://bucket/db",
            layer="layer",
            query="query",
            partitions=["year", "month", "day"],
        )

        pipeline.load_and_register(mock.MagicMock(), format_options="DELTA")

        mock_resolver.sync_to_secondary_catalog.assert_not_called()
