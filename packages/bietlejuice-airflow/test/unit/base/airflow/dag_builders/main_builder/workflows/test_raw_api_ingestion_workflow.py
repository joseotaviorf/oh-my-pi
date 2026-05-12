"""
Unit tests for RawAPIIngestionWorkflow.

Tests the workflow class that orchestrates DAG creation for API ingestion workflows.

Uses lazy import of RawAPIIngestionWorkflow to avoid loading BaseWorkflow, JiraOpsCallback,
TaskCreatorFactory, ReprocessingGuardTaskCreator, and DatasetService during test collection.
That prevents test order sensitivity in test_reprocessing_guard_task_creator,
test_jiraops_callback, and test_dataset_service (see tests/unit/conftest.py).
"""

from unittest.mock import Mock, patch

import pytest

from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TestRawAPIIngestionWorkflow:
    """Test suite for RawAPIIngestionWorkflow class."""

    @pytest.fixture(scope="class")
    def workflow_class(self):
        from bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_api_ingestion_workflow import (
            RawAPIIngestionWorkflow,
        )

        return RawAPIIngestionWorkflow

    class _DummyTask:
        """Minimal task stub supporting Airflow's `>>` chaining."""

        def __init__(self, task_id: str):
            self.task_id = task_id

        def __rshift__(self, other):  # noqa: D401
            return other

    @pytest.fixture
    def mock_config_service(self):
        """Create a mock configuration service."""
        config_service = Mock()
        config_service.get_config = Mock(return_value="test-bucket")
        return config_service

    @pytest.fixture
    def base_dag_args(self):
        """Base DAG arguments for testing."""
        return {
            "name": "test_api_dag",
            "owner": "Data Engineering",
            "schedule_interval": "0 0 * * *",
        }

    @pytest.fixture
    def base_workflow_args(self):
        """Base workflow arguments for testing."""
        return {
            "type": "api_ingestion",
            "layer": "raw",
            "tables_customization": {
                "events": {
                    "endpoint_path": "events",
                    "params": {
                        "after_time": "load_start_date",
                        "before_time": "load_end_date",
                    },
                }
            },
            "api_base_url": "https://api.example.com/",
            "authentication": {
                "strategy": "oauth2_client_credentials",
                "secret_key": "TEST_SECRET",
                "token_url": "https://api.example.com/token",
            },
            "api_policies": {
                "rate_limiting": {"strategy": "fixed_delay", "delay_seconds": 1.0},
                "pagination": {
                    "strategy": "cursor",
                    "cursor_param": "cursor",
                    "page_size": 100,
                },
            },
        }

    @pytest.fixture
    def base_cluster_args(self):
        """Base cluster arguments for testing."""
        return {
            "type": "databricks_16_4_min_memory_cluster",
            "databricks_conn_id": "databricks_new",
        }

    @pytest.fixture
    def patch_configuration_service(self, mock_config_service):
        """Patch ConfigurationService and yield the mock class."""
        with patch(
            "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ConfigurationService"
        ) as mock_cls:
            mock_cls.return_value = mock_config_service
            yield mock_cls

    def test_set_default_spark_job_config_with_empty_workflow_args(
        self,
        workflow_class,
        patch_configuration_service,
        base_dag_args,
        base_cluster_args,
    ):
        """Test that default Spark job config is set when workflow_args is empty."""
        workflow_args = {"tables_customization": {"events": {}}}

        workflow = workflow_class(base_dag_args, workflow_args, base_cluster_args)
        workflow._set_default_spark_job_config()

        assert workflow.workflow_args["load_spark_job"] == "load_api_ingestion_raw"
        assert workflow.workflow_args["spark_job_prefix"] == "base"
        assert "spark_job_arguments" in workflow.workflow_args
        assert len(workflow.workflow_args["spark_job_arguments"]) == 9
        assert "{environment}" in workflow.workflow_args["spark_job_arguments"]
        assert "{dag_name}" in workflow.workflow_args["spark_job_arguments"]

    def test_set_default_spark_job_config_preserves_existing_values(
        self,
        workflow_class,
        patch_configuration_service,
        base_dag_args,
        base_cluster_args,
    ):
        """Test that existing values in workflow_args are not overridden."""
        workflow_args = {
            "tables_customization": {"events": {}},
            "load_spark_job": "custom_job",
            "spark_job_prefix": "custom_prefix",
            "spark_job_arguments": ["custom", "args"],
        }

        workflow = workflow_class(base_dag_args, workflow_args, base_cluster_args)
        workflow._set_default_spark_job_config()

        assert workflow.workflow_args["load_spark_job"] == "custom_job"
        assert workflow.workflow_args["spark_job_prefix"] == "custom_prefix"
        assert workflow.workflow_args["spark_job_arguments"] == ["custom", "args"]

    def test_set_default_spark_job_config_partial_override(
        self,
        workflow_class,
        patch_configuration_service,
        base_dag_args,
        base_cluster_args,
    ):
        """Test that only missing values get defaults, existing ones are preserved."""
        workflow_args = {
            "tables_customization": {"events": {}},
            "load_spark_job": "custom_job",
        }

        workflow = workflow_class(base_dag_args, workflow_args, base_cluster_args)
        workflow._set_default_spark_job_config()

        assert workflow.workflow_args["load_spark_job"] == "custom_job"  # Preserved
        assert workflow.workflow_args["spark_job_prefix"] == "base"  # Default applied
        assert (
            len(workflow.workflow_args["spark_job_arguments"]) == 9
        )  # Default applied

    def test_set_default_spark_job_config_default_arguments_content(
        self,
        workflow_class,
        patch_configuration_service,
        base_dag_args,
        base_cluster_args,
    ):
        """Test that default spark_job_arguments contain all required placeholders."""
        workflow_args = {"tables_customization": {"events": {}}}

        workflow = workflow_class(base_dag_args, workflow_args, base_cluster_args)
        workflow._set_default_spark_job_config()

        expected_args = [
            "{environment}",
            "{bucket}",
            "{dag_name}",
            "{table_name}",
            "{{ data_interval_start | ds }}",
            "{partitions}",
            "{extraction_type}",
            "{load_start_date}",
            "{load_end_date}",
        ]
        assert workflow.workflow_args["spark_job_arguments"] == expected_args

    def test_get_raw_tables(
        self,
        workflow_class,
        patch_configuration_service,
        base_dag_args,
        base_workflow_args,
        base_cluster_args,
    ):
        """Test that _get_raw_tables returns correct TableAttributes for all tables."""
        workflow = workflow_class(base_dag_args, base_workflow_args, base_cluster_args)

        raw_tables = workflow._get_raw_tables()

        assert len(raw_tables) == 1
        assert raw_tables[0].table_name == "events"
        assert raw_tables[0].layer == LayerEnum.RAW

    def test_get_raw_tables_multiple_tables(
        self,
        workflow_class,
        patch_configuration_service,
        base_dag_args,
        base_cluster_args,
    ):
        """Test that _get_raw_tables handles multiple tables correctly."""
        workflow_args = {
            "type": "api_ingestion",
            "layer": "raw",
            "tables_customization": {
                "events": {"endpoint_path": "events"},
                "users": {"endpoint_path": "users"},
                "sessions": {"endpoint_path": "sessions"},
            },
        }
        workflow = workflow_class(base_dag_args, workflow_args, base_cluster_args)

        raw_tables = workflow._get_raw_tables()

        assert len(raw_tables) == 3
        table_names = [table.table_name for table in raw_tables]
        assert "events" in table_names
        assert "users" in table_names
        assert "sessions" in table_names

    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_api_ingestion_workflow.DAGPackagesPathService.list_queries_files_in_composer"
    )
    def test_get_clean_tables(
        self,
        mock_list_queries_files,
        workflow_class,
        patch_configuration_service,
        base_dag_args,
        base_workflow_args,
        base_cluster_args,
    ):
        """Test that _get_clean_tables converts raw tables to clean layer correctly."""
        mock_list_queries_files.return_value = [
            "events"
        ]  # Mock: query file exists for "events"
        workflow = workflow_class(base_dag_args, base_workflow_args, base_cluster_args)
        raw_tables = workflow._get_raw_tables()

        clean_tables = workflow._get_clean_tables(raw_tables)

        assert len(clean_tables) == 1
        assert (
            clean_tables[0].table_name == "events"
        )  # Uses original name if clean_table_name not specified
        assert clean_tables[0].layer == LayerEnum.CLEAN

    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_api_ingestion_workflow.DAGPackagesPathService.list_queries_files_in_composer"
    )
    def test_get_clean_tables_with_clean_table_name(
        self,
        mock_list_queries_files,
        workflow_class,
        patch_configuration_service,
        base_dag_args,
        base_cluster_args,
    ):
        """Test that _get_clean_tables uses clean_table_name when specified."""
        mock_list_queries_files.return_value = [
            "events_clean"
        ]  # Mock: query file exists for "events_clean"
        workflow_args = {
            "type": "api_ingestion",
            "layer": "raw",
            "tables_customization": {
                "api_events": {
                    "endpoint_path": "events",
                    "clean_table_name": "events_clean",  # Custom clean name
                }
            },
        }
        workflow = workflow_class(base_dag_args, workflow_args, base_cluster_args)
        raw_tables = workflow._get_raw_tables()

        clean_tables = workflow._get_clean_tables(raw_tables)

        assert len(clean_tables) == 1
        assert clean_tables[0].table_name == "events_clean"  # Uses clean_table_name
        assert clean_tables[0].layer == LayerEnum.CLEAN

    def test_max_tables_per_cluster(
        self,
        workflow_class,
        patch_configuration_service,
        base_dag_args,
        base_workflow_args,
        base_cluster_args,
    ):
        """Test that MAX_TABLES_PER_CLUSTER is set correctly."""
        workflow = workflow_class(base_dag_args, base_workflow_args, base_cluster_args)

        assert workflow.MAX_TABLES_PER_CLUSTER == 20

    def test_create_all_tasks_accepts_inner_dependencies_alias(
        self,
        workflow_class,
        patch_configuration_service,
        base_dag_args,
        base_cluster_args,
    ):
        """`inner_dependencies` should be accepted as alias for raw inner deps."""

        workflow_args = {
            "type": "api_ingestion",
            "layer": "raw",
            "api_base_url": "https://api.example.com/",
            "tables_customization": {
                "a": {"endpoint_path": "a"},
                "b": {"endpoint_path": "b"},
            },
            "authentication": {
                "strategy": "oauth2_client_credentials",
                "secret_key": "TEST_SECRET",
                "token_url": "https://api.example.com/token",
            },
            "inner_dependencies": {"b": ["a"]},
        }

        workflow = workflow_class(base_dag_args, workflow_args, base_cluster_args)

        workflow.execute_job_cluster_task_creator = Mock()
        workflow.execute_job_cluster_task_creator.create_task.return_value = (
            self._DummyTask("execute_cluster")
        )
        workflow.dummy_job_cluster_finished_task_creator = Mock()
        workflow.dummy_job_cluster_finished_task_creator.create_task.return_value = (
            self._DummyTask("job_cluster_finished")
        )

        workflow._create_raw_tasks = Mock(
            side_effect=lambda *_args, **_kwargs: (
                self._DummyTask("raw_first"),
                self._DummyTask("raw_last"),
            )
        )
        workflow._set_inner_dependencies = Mock()

        raw_tables = [
            Mock(table_name="a", table_customization={}),
            Mock(table_name="b", table_customization={}),
        ]
        workflow._create_all_tasks(
            all_raw_tables=raw_tables,
            all_clean_tables=[],
            tables_customization=workflow_args["tables_customization"],
        )

        assert workflow._set_inner_dependencies.call_count == 1
        assert (
            workflow._set_inner_dependencies.call_args.kwargs["inner_dependencies_key"]
            == "inner_dependencies"
        )
