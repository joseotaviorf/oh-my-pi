import pytest
from unittest import mock
from unittest.mock import Mock

from bietlejuice.pipeline.dataframe_delta_table_loader_pipeline import (
    DataFrameDeltaTableLoaderPipeline,
)
from bietlejuice.base.databricks.table_privileges import TablePrivileges


class TestDataFrameDeltaTableLoaderPipeline:
    @pytest.fixture(autouse=True)
    def mock_spark_client(self):
        with mock.patch(
            "bietlejuice.pipeline.dataframe_delta_table_loader_pipeline.SparkClient"
        ) as spark_client:
            yield spark_client

    @pytest.fixture(autouse=True)
    def mock_spark_metastore_service(self):
        with mock.patch(
            "bietlejuice.pipeline.dataframe_delta_table_loader_pipeline.SparkMetastoreService"
        ) as spark_metastore_service:
            yield spark_metastore_service

    @pytest.fixture(autouse=True)
    def mock_delta_loader(self):
        with mock.patch(
            "bietlejuice.pipeline.dataframe_delta_table_loader_pipeline.DeltaLoader"
        ) as delta_loader:
            yield delta_loader

    @pytest.fixture(autouse=True)
    def mock_unity_catalog_helper(self):
        with mock.patch(
            "bietlejuice.pipeline.dataframe_delta_table_loader_pipeline.UnityCatalogHelper"
        ) as unity_catalog_helper:
            unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = True
            yield unity_catalog_helper

    @pytest.fixture
    def mock_dataframe(self):
        """Mock Spark DataFrame"""
        mock_df = Mock()
        mock_df.count.return_value = 100
        return mock_df

    @pytest.fixture
    def mock_table_privileges(self):
        """Mock TablePrivileges object"""
        mock_privileges = Mock(spec=TablePrivileges)
        return mock_privileges

    @pytest.fixture
    def pipeline_params(self, mock_dataframe):
        """Default parameters for pipeline initialization"""
        return {
            "database_name": "test_database",
            "table_name": "test_table",
            "database_location": "s3://test-bucket/test_database/",
            "layer": "raw",
            "dataframe": mock_dataframe,
            "partitions": ["partition_col"],
            "target_database_name": "target_database",
            "target_database_location": "s3://test-bucket/target_database/",
            "merge_schema": True,
            "merge_on": ["id"],
            "when_matched_update_condition": "source.updated_at > target.updated_at",
            "when_not_matched_insert_condition": "source.is_active = true",
            "when_matched_delete_condition": "source.is_deleted = true",
            "when_not_matched_by_source_delete_condition": "target.is_deleted = true",
            "when_matched_operation": {"status": "updated"},
            "when_not_matched_operation": {"status": "new"},
        }

    def test_initialization_with_all_params(
        self, pipeline_params, mock_table_privileges
    ):
        """Test pipeline initialization with all parameters"""
        # Arrange & Act
        pipeline_params["table_privileges"] = mock_table_privileges
        pipeline = DataFrameDeltaTableLoaderPipeline(**pipeline_params)

        # Assert
        assert pipeline.database_name == "test_database"
        assert pipeline.table_name == "test_table"
        assert pipeline.database_location == "s3://test-bucket/test_database/"
        assert pipeline.layer == "raw"
        assert pipeline.dataframe == pipeline_params["dataframe"]
        assert pipeline.target_database_name == "target_database"
        assert pipeline.target_database_location == "s3://test-bucket/target_database/"
        assert pipeline.partitions == ["partition_col"]
        assert pipeline.merge_schema is True
        assert pipeline.merge_on == ["id"]
        assert (
            pipeline.when_matched_update_condition
            == "source.updated_at > target.updated_at"
        )
        assert pipeline.when_not_matched_insert_condition == "source.is_active = true"
        assert pipeline.when_matched_delete_condition == "source.is_deleted = true"
        assert (
            pipeline.when_not_matched_by_source_delete_condition
            == "target.is_deleted = true"
        )
        assert pipeline.when_matched_operation == {"status": "updated"}
        assert pipeline.when_not_matched_operation == {"status": "new"}
        assert pipeline.table_privileges == mock_table_privileges

    def test_initialization_with_minimal_params(self, mock_dataframe):
        """Test pipeline initialization with minimal required parameters"""
        # Arrange & Act
        pipeline = DataFrameDeltaTableLoaderPipeline(
            database_name="test_db",
            table_name="test_table",
            database_location="s3://bucket/db/",
            layer="raw",
            dataframe=mock_dataframe,
        )

        # Assert
        assert pipeline.database_name == "test_db"
        assert pipeline.table_name == "test_table"
        assert pipeline.database_location == "s3://bucket/db/"
        assert pipeline.layer == "raw"
        assert pipeline.dataframe == mock_dataframe
        assert pipeline.target_database_name == "test_db"  # defaults to database_name
        assert (
            pipeline.target_database_location == "s3://bucket/db/"
        )  # defaults to database_location
        assert pipeline.partitions == []  # default empty list
        assert pipeline.merge_schema is True  # default
        assert pipeline.merge_on is None  # default
        assert pipeline.table_privileges is None  # default

    def test_run_creates_databases_and_loads_data(
        self, pipeline_params, mock_spark_client, mock_spark_metastore_service
    ):
        """Test that run() method creates databases and loads data"""
        # Arrange
        pipeline = DataFrameDeltaTableLoaderPipeline(**pipeline_params)

        # Act
        pipeline.run()

        # Assert
        # Verify SparkClient is instantiated (called twice: once in run(), once in _load_and_register())
        assert mock_spark_client.call_count == 2

        # Verify SparkMetastoreService is instantiated with SparkClient
        assert mock_spark_metastore_service.call_count == 2
        mock_spark_metastore_service.assert_any_call(mock_spark_client.return_value)

        # Verify databases are created
        metastore_service_instance = mock_spark_metastore_service.return_value
        assert metastore_service_instance.create_database.call_count == 2
        metastore_service_instance.create_database.assert_any_call("target_database")
        metastore_service_instance.create_database.assert_any_call("test_database")

    def test_run_with_udfs(self, pipeline_params, mock_spark_client):
        """Test that run() method registers UDFs when specified"""
        # Arrange
        pipeline_params["spark_session_configs"] = {"udfs": ["test_udf1", "test_udf2"]}
        pipeline = DataFrameDeltaTableLoaderPipeline(**pipeline_params)

        with mock.patch.object(pipeline, "_register_udf") as mock_register_udf:
            # Act
            pipeline.run()

            # Assert
            assert mock_register_udf.call_count == 2
            mock_register_udf.assert_any_call(
                mock_spark_client.return_value, "test_udf1"
            )
            mock_register_udf.assert_any_call(
                mock_spark_client.return_value, "test_udf2"
            )

    def test_load_and_register_basic_functionality(
        self, pipeline_params, mock_delta_loader, mock_spark_metastore_service
    ):
        """Test _load_and_register method basic functionality"""
        # Arrange
        pipeline = DataFrameDeltaTableLoaderPipeline(**pipeline_params)

        # Act
        pipeline._load_and_register()

        # Assert
        # Verify DeltaLoader is instantiated with spark session
        mock_delta_loader.assert_called_once_with(spark=pipeline.spark)

        # Verify load_table is called with correct parameters
        delta_loader_instance = mock_delta_loader.return_value
        delta_loader_instance.load_table.assert_called_once_with(
            table_name="target_database.test_table",
            path="s3://test-bucket/target_database/test_table",
            source_df=pipeline_params["dataframe"],
            partition_by=["partition_col"],
            merge_schema=True,
            merge_on=["id"],
            when_not_matched_insert_condition="source.is_active = true",
            when_matched_update_condition="source.updated_at > target.updated_at",
            when_matched_delete_condition="source.is_deleted = true",
            when_not_matched_by_source_delete_condition="target.is_deleted = true",
            when_matched_operation={"status": "updated"},
            when_not_matched_operation={"status": "new"},
        )

        # Verify table refresh is called
        metastore_service_instance = mock_spark_metastore_service.return_value
        metastore_service_instance.refresh_table.assert_called_once_with(
            "target_database", "test_table"
        )

    def test_load_and_register_applies_table_privileges(
        self, pipeline_params, mock_table_privileges, mock_unity_catalog_helper
    ):
        """Test that _load_and_register applies table privileges when available"""
        # Arrange
        pipeline_params["table_privileges"] = mock_table_privileges
        pipeline = DataFrameDeltaTableLoaderPipeline(**pipeline_params)

        # Act
        pipeline._load_and_register()

        # Assert
        # Verify Unity Catalog check is called
        mock_unity_catalog_helper.is_cluster_unity_catalog_enabled.assert_called_once()

        # Verify table privileges are applied
        mock_table_privileges.apply.assert_called_once()

    def test_load_and_register_skips_privileges_when_unity_catalog_disabled(
        self, pipeline_params, mock_table_privileges, mock_unity_catalog_helper
    ):
        """Test that privileges are not applied when Unity Catalog is disabled"""
        # Arrange
        mock_unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = False
        pipeline_params["table_privileges"] = mock_table_privileges
        pipeline = DataFrameDeltaTableLoaderPipeline(**pipeline_params)

        # Act
        pipeline._load_and_register()

        # Assert
        # Verify Unity Catalog check is called
        mock_unity_catalog_helper.is_cluster_unity_catalog_enabled.assert_called_once()

        # Verify table privileges are NOT applied
        mock_table_privileges.apply.assert_not_called()

    def test_load_and_register_skips_privileges_when_none(
        self, pipeline_params, mock_unity_catalog_helper
    ):
        """Test that nothing happens when table_privileges is None"""
        # Arrange
        pipeline_params["table_privileges"] = None
        pipeline = DataFrameDeltaTableLoaderPipeline(**pipeline_params)

        # Act
        pipeline._load_and_register()

        # Assert
        # Unity Catalog check should not be called if no privileges
        mock_unity_catalog_helper.is_cluster_unity_catalog_enabled.assert_not_called()

    @mock.patch("bietlejuice.base.udfs.udf_enum.UDFEnum")
    def test_register_udf_success(self, mock_udf_enum, pipeline_params):
        """Test successful UDF registration"""
        # Arrange
        pipeline = DataFrameDeltaTableLoaderPipeline(**pipeline_params)
        mock_spark_client = Mock()
        mock_udf_function = Mock()
        mock_udf_enum.get_udf.return_value = mock_udf_function

        # Act
        pipeline._register_udf(mock_spark_client, "test_udf")

        # Assert
        mock_udf_enum.get_udf.assert_called_once_with(udf_identifier="test_udf")
        mock_spark_client.conn.udf.register.assert_called_once_with(
            "test_udf", mock_udf_function
        )

    @mock.patch("bietlejuice.base.udfs.udf_enum.UDFEnum")
    def test_register_udf_not_found(self, mock_udf_enum, pipeline_params):
        """Test UDF registration when UDF is not found"""
        # Arrange
        pipeline = DataFrameDeltaTableLoaderPipeline(**pipeline_params)
        mock_spark_client = Mock()
        mock_udf_enum.get_udf.return_value = None

        # Act
        pipeline._register_udf(mock_spark_client, "non_existent_udf")

        # Assert
        mock_udf_enum.get_udf.assert_called_once_with(udf_identifier="non_existent_udf")
        # Should not attempt to register if UDF is not found
        mock_spark_client.conn.udf.register.assert_not_called()

    def test_run_integration_with_privileges(
        self, pipeline_params, mock_table_privileges, mock_unity_catalog_helper
    ):
        """Test full integration run with table privileges"""
        # Arrange
        pipeline_params["table_privileges"] = mock_table_privileges
        pipeline = DataFrameDeltaTableLoaderPipeline(**pipeline_params)

        # Act
        pipeline.run()

        # Assert - verify the full workflow
        # This should create databases, load data, refresh table, and apply privileges
        mock_unity_catalog_helper.is_cluster_unity_catalog_enabled.assert_called_once()
        mock_table_privileges.apply.assert_called_once()

    def test_path_construction(self, pipeline_params, mock_delta_loader):
        """Test that S3 paths are constructed correctly"""
        # Arrange
        pipeline = DataFrameDeltaTableLoaderPipeline(**pipeline_params)

        # Act
        pipeline._load_and_register()

        # Assert - the path should be target_database_location + table_name
        expected_path = "s3://test-bucket/target_database/test_table"
        # Verify the path is constructed correctly by checking the mock call
        delta_loader_instance = mock_delta_loader.return_value
        call_args = delta_loader_instance.load_table.call_args
        actual_path = call_args.kwargs["path"]
        assert actual_path == expected_path

    def test_database_defaults(self, mock_dataframe):
        """Test that target database defaults to source database when not specified"""
        # Arrange & Act
        pipeline = DataFrameDeltaTableLoaderPipeline(
            database_name="source_db",
            table_name="test_table",
            database_location="s3://bucket/source/",
            layer="raw",
            dataframe=mock_dataframe,
            # target_database_name and target_database_location not specified
        )

        # Assert
        assert pipeline.target_database_name == "source_db"
        assert pipeline.target_database_location == "s3://bucket/source/"

    def test_spark_session_configs_defaults(self, mock_dataframe):
        """Test that spark_session_configs defaults to empty dict"""
        # Arrange & Act
        pipeline = DataFrameDeltaTableLoaderPipeline(
            database_name="test_db",
            table_name="test_table",
            database_location="s3://bucket/db/",
            layer="raw",
            dataframe=mock_dataframe,
        )

        # Assert
        assert pipeline.spark_session_configs == {}
