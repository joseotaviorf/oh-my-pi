"""Unit tests for RawCDCWorkflow max_tables_per_cluster configuration."""

from contextlib import nullcontext as does_not_raise
from unittest.mock import MagicMock, Mock, patch

import pytest

from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TestRawCDCWorkflowMaxTablesPerCluster:
    @pytest.fixture(scope="class")
    def workflow_class(self):
        from bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_cdc_workflow import (
            RawCDCWorkflow,
        )

        return RawCDCWorkflow

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
            "name": "test_cdc_dag",
            "owner": "Data Engineering",
            "schedule_interval": "0 0 * * *",
        }

    @pytest.fixture
    def base_cluster_args(self):
        return {
            "type": "databricks_16_4_min_memory_cluster",
            "databricks_conn_id": "databricks_new",
        }

    def _workflow_args(self, n_tables: int, max_tables_per_cluster=None):
        workflow_args = {
            "type": "cdc",
            "layer": "raw",
            "database_type": "postgres",
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
            self._workflow_args(n_tables=1, max_tables_per_cluster=8),
            base_cluster_args,
        )

        assert workflow._max_tables_per_cluster() == 8

    @pytest.mark.parametrize(
        "n_tables, max_per_cluster, expected_clusters",
        [
            (1, 13, 1),
            (12, 13, 1),
            (13, 13, 2),
            (74, 13, 6),
            (74, 25, 3),
        ],
    )
    def test_create_all_tasks_splits_by_max_tables_per_cluster(
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

        transactional_tables = [
            Mock(table_name=f"table_{i}", layer=LayerEnum.TRANSACTIONAL)
            for i in range(n_tables)
        ]
        raw_tables = [
            Mock(table_name=f"table_{i}", layer=LayerEnum.RAW) for i in range(n_tables)
        ]
        clean_tables = [
            Mock(table_name=f"table_{i}", layer=LayerEnum.CLEAN)
            for i in range(n_tables)
        ]

        with patch.object(workflow, "_create_all_tasks_for_cluster") as mock_create:
            workflow.dummy_job_cluster_finished_task_creator = Mock()
            workflow.dummy_job_cluster_finished_task_creator.create_task.return_value = Mock()
            workflow._create_all_tasks(
                transactional_tables,
                raw_tables,
                clean_tables,
                workflow.workflow_args["tables_customization"],
            )

        assert mock_create.call_count == expected_clusters

    @pytest.mark.parametrize(
        "max_tables_per_cluster, expectation",
        [
            (8, does_not_raise()),
            (1, does_not_raise()),
            (0, pytest.raises(AssertionError)),
        ],
    )
    def test_cdc_declaration_accepts_max_tables_per_cluster(
        self, max_tables_per_cluster, expectation
    ):
        from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_declaration_validator import (
            DAGDeclarationValidator,
        )

        dag_declaration = {
            "dag": {"name": "test_cdc_dag", "owner": "Data Engineering"},
            "workflow": {
                "type": "cdc",
                "layer": "raw",
                "database_type": "postgres",
                "tables_customization": {"SomeTable": {}},
                "max_tables_per_cluster": max_tables_per_cluster,
            },
        }

        with expectation:
            DAGDeclarationValidator().validate(dag_declaration=dag_declaration)


class TestRawCDCWorkflowProfiling:
    @pytest.fixture
    def workflow(self):
        from bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_cdc_workflow import (
            RawCDCWorkflow,
        )

        with patch(
            "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ConfigurationService"
        ):
            return RawCDCWorkflow(
                {
                    "name": "test_cdc_dag",
                    "owner": "Data Engineering",
                    "schedule_interval": "0 0 * * *",
                },
                {
                    "type": "cdc",
                    "layer": "raw",
                    "database_type": "postgres",
                    "tables_customization": {"traces": {}},
                },
                {
                    "type": "databricks_16_4_min_memory_cluster",
                    "databricks_conn_id": "databricks_new",
                },
            )

    def test_create_clean_tasks_adds_profiling_when_gated_on(self, workflow):
        # arrange
        load_task = MagicMock(name="load_clean")
        profiling_task = MagicMock(name="profiling_clean")
        dag_final_tasks = MagicMock(name="dag_final")
        optimize_clean_task = MagicMock(name="optimize_clean")
        table_attrs = Mock()
        workflow._check_include_sync_hive_tasks = Mock(return_value=False)
        workflow._check_include_data_quality_task = Mock(return_value=False)
        workflow._check_include_profiling_task = Mock(return_value=True)
        workflow.load_cdc_clean_task_creator = Mock()
        workflow.load_cdc_clean_task_creator.create_task.return_value = load_task
        workflow.profiling_task_creator = Mock()
        workflow.profiling_task_creator.create_task.return_value = profiling_task

        # act
        first, last = workflow._create_clean_tasks(
            table_attrs, optimize_clean_task, dag_final_tasks
        )

        # assert
        assert first is load_task
        assert last is load_task
        workflow.profiling_task_creator.create_task.assert_called_once_with(table_attrs)
        load_task.__rshift__.assert_any_call(profiling_task)

    def test_create_clean_tasks_skips_profiling_when_gated_off(self, workflow):
        # arrange
        load_task = MagicMock(name="load_clean")
        dag_final_tasks = MagicMock(name="dag_final")
        optimize_clean_task = MagicMock(name="optimize_clean")
        table_attrs = Mock()
        workflow._check_include_sync_hive_tasks = Mock(return_value=False)
        workflow._check_include_data_quality_task = Mock(return_value=False)
        workflow._check_include_profiling_task = Mock(return_value=False)
        workflow.load_cdc_clean_task_creator = Mock()
        workflow.load_cdc_clean_task_creator.create_task.return_value = load_task
        workflow.profiling_task_creator = Mock()

        # act
        workflow._create_clean_tasks(table_attrs, optimize_clean_task, dag_final_tasks)

        # assert
        workflow.profiling_task_creator.create_task.assert_not_called()
