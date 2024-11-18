import pytest
from unittest import mock
from bietlejuice.pipeline.full_table_loader_pipeline import FullTableLoaderPipeline


class TestFullTableLoaderPipeline:
    @pytest.fixture(autouse=True)
    def mock_s3_loader(self):
        with mock.patch(
            "bietlejuice.pipeline.full_table_loader_pipeline.S3Loader"
        ) as s3_loader:
            yield s3_loader

    @pytest.fixture(autouse=True)
    def mock_spark_metastore_service(self):
        with mock.patch(
            "bietlejuice.pipeline.full_table_loader_pipeline.SparkMetastoreService"
        ) as spark_metastore_service:
            yield spark_metastore_service

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
