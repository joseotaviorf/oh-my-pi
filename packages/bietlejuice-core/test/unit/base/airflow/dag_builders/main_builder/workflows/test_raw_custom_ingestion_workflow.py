"""Unit tests for RawCustomIngestionWorkflow max_tables_per_cluster configuration."""

from unittest.mock import Mock, patch

import pytest


class TestRawCustomIngestionWorkflowMaxTablesPerCluster:
    @pytest.fixture(scope="class")
    def workflow_class(self):
        from bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_custom_ingestion_workflow import (
            RawCustomIngestionWorkflow,
        )

        return RawCustomIngestionWorkflow

    @pytest.fixture
    def patch_configuration_service(self):
        config_service = Mock()
        config_service.get_config = Mock(return_value="test-bucket")
        with patch(
            "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ConfigurationService"
        ) as mock_cls:
            mock_cls.return_value = config_service
            yield mock_cls

    @pytest.fixture
    def base_dag_args(self):
        return {
            "name": "test_custom_ingestion_dag",
            "owner": "Data Engineering",
            "schedule_interval": "0 0 * * *",
        }

    @pytest.fixture
    def base_cluster_args(self):
        return {
            "type": "emr_7_12_consolidation_xs_memory_fleet_cluster",
            "custom_configurations": {},
        }

    def _workflow_args(self, n_tables: int, max_tables_per_cluster=None):
        workflow_args = {
            "type": "custom_ingestion",
            "layer": "raw",
            "load_spark_job": "load_test_raw",
            "tables_customization": {f"table_{i}": {} for i in range(n_tables)},
        }
        if max_tables_per_cluster is not None:
            workflow_args["max_tables_per_cluster"] = max_tables_per_cluster
        return workflow_args

    def test_max_tables_per_cluster_defaults_to_class_constant(
        self,
        workflow_class,
        patch_configuration_service,
        base_dag_args,
        base_cluster_args,
    ):
        workflow = workflow_class(
            base_dag_args,
            self._workflow_args(n_tables=1),
            base_cluster_args,
        )

        assert (
            workflow._max_tables_per_cluster() == workflow_class.MAX_TABLES_PER_CLUSTER
        )

    def test_max_tables_per_cluster_reads_workflow_override(
        self,
        workflow_class,
        patch_configuration_service,
        base_dag_args,
        base_cluster_args,
    ):
        workflow = workflow_class(
            base_dag_args,
            self._workflow_args(n_tables=1, max_tables_per_cluster=99999),
            base_cluster_args,
        )

        assert workflow._max_tables_per_cluster() == 99999

    @pytest.mark.parametrize(
        "n_tables, max_per_cluster, expected_clusters",
        [
            (1, 14, 1),
            (14, 14, 1),
            (15, 14, 2),
            (74, 14, 6),
            (74, 99999, 1),
        ],
    )
    def test_create_all_tasks_in_clusters_splits_by_max_tables_per_cluster(
        self,
        workflow_class,
        patch_configuration_service,
        base_dag_args,
        base_cluster_args,
        n_tables,
        max_per_cluster,
        expected_clusters,
    ):
        workflow = workflow_class(
            base_dag_args,
            self._workflow_args(
                n_tables=n_tables, max_tables_per_cluster=max_per_cluster
            ),
            base_cluster_args,
        )

        with patch.object(workflow, "_create_tasks_for_cluster") as mock_create:
            workflow.dummy_job_cluster_finished_task_creator = Mock()
            workflow.dummy_job_cluster_finished_task_creator.create_task.return_value = Mock()
            workflow._create_all_tasks_in_clusters()

        assert mock_create.call_count == expected_clusters
