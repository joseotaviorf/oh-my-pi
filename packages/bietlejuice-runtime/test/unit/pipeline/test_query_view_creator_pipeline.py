from unittest import mock

import pytest

from bietlejuice.pipeline.query_view_creator_pipeline import QueryViewCreatorPipeline


class TestQueryViewCreatorPipeline:
    @pytest.fixture(autouse=True)
    def mock_spark_client(self):
        with mock.patch(
            "bietlejuice.pipeline.query_view_creator_pipeline.SparkClient"
        ) as spark_client:
            yield spark_client

    @pytest.fixture(autouse=True)
    def mock_loader_metastore_service(self):
        with mock.patch(
            "bietlejuice.pipeline.query_view_creator_pipeline.MetastoreServiceFactory.create_loader_metastore_service",
            return_value=mock.MagicMock(),
        ) as factory_mock:
            yield factory_mock

    @pytest.fixture(autouse=True)
    def mock_sqlglot(self):
        with mock.patch(
            "bietlejuice.pipeline.query_view_creator_pipeline.sqlglot"
        ) as sqlglot:
            sqlglot.transpile.return_value = [
                "SELECT * FROM source_table -- Trino version"
            ]
            yield sqlglot

    @pytest.fixture
    def pipeline(self):
        return QueryViewCreatorPipeline(
            database_name="test_db",
            view_name="test_view",
            layer="enrich",
            query="SELECT * FROM source_table WHERE param = '{param1}'",
            query_template_params={"param1": "value1"},
            spark_session_configs={},
            env="test",
            spark=None,
            table_privileges=None,
            sync=["databricks"],
            sql_dialect="databricks",
        )

    def test_init_with_defaults(self):
        # Arrange & Act
        pipeline = QueryViewCreatorPipeline(
            database_name="test_db",
            view_name="test_view",
            layer="enrich",
            query="SELECT * FROM table",
        )

        # Assert
        assert pipeline.query_template_params == {}
        assert pipeline.spark_session_configs == {}
        assert pipeline.env is None
        assert pipeline.spark is None
        assert pipeline.table_privileges is None
        assert pipeline.sync == ("databricks",)
        assert pipeline.sql_dialect == "databricks"

    def test_run_creates_databricks_view(self, pipeline, mock_spark_client):
        # Arrange
        mock_spark_client_instance = mock.MagicMock()
        mock_spark_client.return_value = mock_spark_client_instance

        with (
            mock.patch.object(
                pipeline, "_create_databricks_view"
            ) as mock_create_databricks,
            mock.patch.object(pipeline, "_create_trino_view") as mock_create_trino,
        ):
            # Act
            pipeline.run()

            # Assert
            mock_create_databricks.assert_called_once_with(
                mock_spark_client_instance,
                "SELECT * FROM source_table WHERE param = 'value1'",
            )
            mock_create_trino.assert_not_called()

    def test_run_creates_databricks_and_trino_views(
        self, mock_spark_client, mock_sqlglot
    ):
        # Arrange
        pipeline = QueryViewCreatorPipeline(
            database_name="test_db",
            view_name="test_view",
            layer="enrich",
            query="SELECT * FROM source_table WHERE param = '{param1}'",
            query_template_params={"param1": "value1"},
            sync=["databricks", "trino"],
            sql_dialect="databricks",
        )
        mock_spark_client_instance = mock.MagicMock()
        mock_spark_client.return_value = mock_spark_client_instance

        with (
            mock.patch.object(
                pipeline, "_create_databricks_view"
            ) as mock_create_databricks,
            mock.patch.object(pipeline, "_create_trino_view") as mock_create_trino,
        ):
            # Act
            pipeline.run()

            # Assert
            mock_create_databricks.assert_called_once_with(
                mock_spark_client_instance,
                "SELECT * FROM source_table WHERE param = 'value1'",
            )
            mock_sqlglot.transpile.assert_called_once_with(
                "SELECT * FROM source_table WHERE param = 'value1'",
                read="databricks",
                write="trino",
            )
            mock_create_trino.assert_called_once_with(
                "SELECT * FROM source_table -- Trino version"
            )

    def test_run_creates_trino_only_view_without_spark_client(self, mock_spark_client):
        # Arrange
        pipeline = QueryViewCreatorPipeline(
            database_name="test_db",
            view_name="test_view",
            layer="dw",
            query="SELECT * FROM source_table WHERE param = '{param1}'",
            query_template_params={"param1": "value1"},
            sync=["trino"],
            sql_dialect="trino",
        )

        with (
            mock.patch.object(pipeline, "_create_databricks_view") as databricks_view,
            mock.patch.object(pipeline, "_create_trino_view") as trino_view,
        ):
            # Act
            pipeline.run()

            # Assert
            databricks_view.assert_not_called()
            trino_view.assert_called_once_with(
                "SELECT * FROM source_table WHERE param = 'value1'"
            )
            mock_spark_client.assert_not_called()

    def test_get_query_for_target_returns_source_when_dialect_matches(
        self, pipeline, mock_sqlglot
    ):
        # Arrange
        formatted_query = "SELECT * FROM source_table"

        # Act
        result = pipeline._get_query_for_target(formatted_query, "databricks")

        # Assert
        assert result == formatted_query
        mock_sqlglot.transpile.assert_not_called()

    def test_get_query_for_target_transpiles_when_dialect_differs(
        self, pipeline, mock_sqlglot
    ):
        # Arrange
        formatted_query = "SELECT * FROM source_table"

        # Act
        result = pipeline._get_query_for_target(formatted_query, "trino")

        # Assert
        assert result == "SELECT * FROM source_table -- Trino version"
        mock_sqlglot.transpile.assert_called_once_with(
            formatted_query, read="databricks", write="trino"
        )

    def test_create_databricks_database_success(
        self, pipeline, mock_loader_metastore_service
    ):
        # Arrange
        mock_spark_client = mock.MagicMock()
        mock_metastore_instance = mock.MagicMock()
        mock_loader_metastore_service.return_value = mock_metastore_instance

        # Act
        pipeline._create_databricks_database(mock_spark_client)

        # Assert
        mock_loader_metastore_service.assert_called_once_with(mock_spark_client)
        mock_metastore_instance.create_database.assert_called_once_with("test_db")

    def test_create_databricks_database_failure(
        self, pipeline, mock_loader_metastore_service
    ):
        # Arrange
        mock_spark_client = mock.MagicMock()
        mock_metastore_instance = mock.MagicMock()
        mock_metastore_instance.create_database.side_effect = Exception(
            "Database creation failed"
        )
        mock_loader_metastore_service.return_value = mock_metastore_instance

        # Act & Assert
        with pytest.raises(Exception, match="Database creation failed"):
            pipeline._create_databricks_database(mock_spark_client)

    def test_create_databricks_view_success(self, pipeline):
        # Arrange
        mock_spark_client = mock.MagicMock()
        formatted_query = "SELECT * FROM source_table WHERE param = 'value1'"

        with mock.patch.object(
            pipeline, "_create_databricks_database"
        ) as mock_create_database:
            # Act
            pipeline._create_databricks_view(mock_spark_client, formatted_query)

            # Assert
            mock_create_database.assert_called_once_with(mock_spark_client)
            mock_spark_client.conn.sql.assert_called_once()
            actual_sql = mock_spark_client.conn.sql.call_args[0][0]
            assert "CREATE OR REPLACE VIEW test_db.test_view AS" in actual_sql
            assert formatted_query in actual_sql

    def test_create_databricks_view_failure(self, pipeline):
        # Arrange
        mock_spark_client = mock.MagicMock()
        mock_spark_client.conn.sql.side_effect = Exception("SQL Error")
        formatted_query = "SELECT * FROM source_table"

        with mock.patch.object(pipeline, "_create_databricks_database"):
            # Act & Assert
            with pytest.raises(Exception, match="SQL Error"):
                pipeline._create_databricks_view(mock_spark_client, formatted_query)

    def test_create_trino_schema_success(self, pipeline):
        # Arrange
        mock_trino_client = mock.MagicMock()

        # Act
        pipeline._create_trino_schema(mock_trino_client)

        # Assert
        mock_trino_client.run.assert_called_once_with(
            "CREATE SCHEMA IF NOT EXISTS delta.test_db"
        )

    def test_create_trino_schema_failure(self, pipeline):
        # Arrange
        mock_trino_client = mock.MagicMock()
        mock_trino_client.run.side_effect = Exception("Schema creation failed")

        # Act & Assert
        with pytest.raises(Exception, match="Schema creation failed"):
            pipeline._create_trino_schema(mock_trino_client)

    def test_create_trino_view_success(self, pipeline, mock_sqlglot):
        # Arrange
        formatted_query = "SELECT * FROM source_table"
        mock_trino_client = mock.MagicMock()

        with (
            mock.patch.object(pipeline, "get_trino_client") as mock_get_trino_client,
            mock.patch.object(pipeline, "_create_trino_schema") as mock_create_schema,
        ):
            mock_get_trino_client.return_value = mock_trino_client

            # Act
            pipeline._create_trino_view(formatted_query)

            # Assert
            mock_get_trino_client.assert_called_once()
            mock_create_schema.assert_called_once_with(mock_trino_client)
            mock_sqlglot.transpile.assert_not_called()
            mock_trino_client.run.assert_called_once()
            actual_sql = mock_trino_client.run.call_args[0][0]
            assert "CREATE OR REPLACE VIEW test_db.test_view AS" in actual_sql
            assert formatted_query in actual_sql

    def test_create_trino_view_failure(self, pipeline):
        # Arrange
        formatted_query = "SELECT * FROM source_table"
        mock_trino_client = mock.MagicMock()
        mock_trino_client.run.side_effect = Exception("Trino query failed")

        with (
            mock.patch.object(pipeline, "get_trino_client") as mock_get_trino_client,
            mock.patch.object(pipeline, "_create_trino_schema"),
        ):
            mock_get_trino_client.return_value = mock_trino_client

            # Act & Assert
            with pytest.raises(Exception, match="Trino query failed"):
                pipeline._create_trino_view(formatted_query)

    def test_get_query_for_target_failure(self, pipeline, mock_sqlglot):
        # Arrange
        formatted_query = "SELECT * FROM source_table"
        mock_sqlglot.transpile.side_effect = Exception("Transpilation failed")

        # Act & Assert
        with pytest.raises(Exception, match="Transpilation failed"):
            pipeline._get_query_for_target(formatted_query, "trino")

    @mock.patch("bietlejuice.pipeline.query_view_creator_pipeline.UnityCatalogHelper")
    def test_run_applies_table_privileges_when_configured(
        self, mock_unity_catalog, pipeline, mock_spark_client
    ):
        # Arrange
        mock_table_privileges = mock.MagicMock()
        pipeline.table_privileges = mock_table_privileges
        mock_unity_catalog.is_cluster_unity_catalog_enabled.return_value = True

        mock_spark_client_instance = mock.MagicMock()
        mock_spark_client.return_value = mock_spark_client_instance

        with mock.patch.object(pipeline, "_create_databricks_view"):
            # Act
            pipeline.run()

            # Assert
            mock_table_privileges.apply.assert_called_once()

    @mock.patch("bietlejuice.pipeline.query_view_creator_pipeline.UnityCatalogHelper")
    def test_run_does_not_apply_table_privileges_for_trino_only_view(
        self, mock_unity_catalog
    ):
        # Arrange
        pipeline = QueryViewCreatorPipeline(
            database_name="test_db",
            view_name="test_view",
            layer="dw",
            query="SELECT * FROM source_table",
            table_privileges=mock.MagicMock(),
            sync=["trino"],
            sql_dialect="trino",
        )

        with mock.patch.object(pipeline, "_create_trino_view"):
            # Act
            pipeline.run()

            # Assert
            pipeline.table_privileges.apply.assert_not_called()
            mock_unity_catalog.is_cluster_unity_catalog_enabled.assert_not_called()
