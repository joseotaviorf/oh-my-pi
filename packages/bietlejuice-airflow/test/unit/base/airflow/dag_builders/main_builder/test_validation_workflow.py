from unittest import mock

import pytest

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.enrich_query_delta_workflow import (
    EnrichQueryDeltaWorkflow,
)
from bietlejuice.base.pipeline.environment_enum import EnvironmentEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class TestValidationWorkflow:
    def test_validation_workflow_flags(self):
        with mock.patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.PROD}):
            workflow = EnrichQueryDeltaWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={"type": "query_delta", "layer": "enrich"},
                cluster_args={"type": "consolidation_s_general_single_node_cluster"},
                dataset_dependencies=mock.MagicMock(),
                is_validation=True,
                validation_config={
                    "cluster": {"type": "consolidation_s_general_single_node_cluster"}
                },
            )

        assert workflow.is_validation is True
        assert workflow.dag_name == "pilot"
        assert workflow.dag_id == "bietlejuice.pilot__validation"
        assert workflow.dataset_dependencies == []

    def test_prod_workflow_keeps_dataset_dependencies(self):
        deps = mock.MagicMock()
        with mock.patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.PROD}):
            workflow = EnrichQueryDeltaWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={"type": "query_delta", "layer": "enrich"},
                cluster_args={"type": "databricks_16_4_med_general_cluster"},
                dataset_dependencies=deps,
            )

        assert workflow.is_validation is False
        assert workflow.dag_name == "pilot"
        assert workflow.dag_id == "bietlejuice.pilot"
        assert workflow.dataset_dependencies is deps

    def test_validation_list_queries_uses_prod_dag_name(self):
        with mock.patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.PROD}):
            workflow = EnrichQueryDeltaWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={"type": "query_delta", "layer": "enrich"},
                cluster_args={"type": "consolidation_s_general_single_node_cluster"},
                dataset_dependencies=mock.MagicMock(),
                is_validation=True,
                validation_config={
                    "cluster": {"type": "consolidation_s_general_single_node_cluster"}
                },
            )

        with mock.patch.object(
            DAGPackagesPathService,
            "list_queries_files_in_composer",
            return_value=["table_a"],
        ) as list_queries:
            tables = workflow._get_tables()

        list_queries.assert_called_once_with(
            dag_name="pilot", layer=workflow.layer.value
        )
        assert len(tables) == 1

    def test_base_workflow_dag_id_suffix_only_when_validation(self):
        with mock.patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.PROD}):
            prod = BaseWorkflow(
                dag_args={"name": "my_dag", "owner": "o"},
                workflow_args={},
                cluster_args={},
            )
            validation = BaseWorkflow(
                dag_args={"name": "my_dag", "owner": "o"},
                workflow_args={},
                cluster_args={},
                is_validation=True,
            )

        assert prod.dag_id == "bietlejuice.my_dag"
        assert validation.dag_id == "bietlejuice.my_dag__validation"
        assert validation.dag_name == "my_dag"

    @pytest.fixture
    def _dag_instance_mocks(self):
        """Patch all Airflow/infrastructure calls needed to exercise dag_instance()."""
        with (
            mock.patch(
                "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.DAG"
            ) as mock_dag,
            mock.patch(
                "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.JiraOpsCallback"
            ),
            mock.patch(
                "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.DatabricksIncidentContextEnricher"
            ),
            mock.patch(
                "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.BaseDAG.get_default_trigger_form_params",
                return_value={},
            ),
            mock.patch.object(
                BaseWorkflow, "_get_start_date", return_value=mock.MagicMock()
            ),
            mock.patch.object(BaseWorkflow, "_get_dag_documentation", return_value=""),
        ):
            yield mock_dag

    def test_validation_dag_has_no_schedule(self, _dag_instance_mocks):
        mock_dag_cls = _dag_instance_mocks
        with mock.patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.PROD}):
            workflow = BaseWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={},
                cluster_args={},
                is_validation=True,
            )
        workflow.dag_instance()
        assert mock_dag_cls.call_args.kwargs["schedule"] is None

    def test_prod_dag_uses_schedule_interval(self, _dag_instance_mocks):
        mock_dag_cls = _dag_instance_mocks
        with mock.patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.PROD}):
            workflow = BaseWorkflow(
                dag_args={
                    "name": "pilot",
                    "owner": "Data Engineering",
                    "schedule_interval": "0 6 * * *",
                },
                workflow_args={},
                cluster_args={},
                is_validation=False,
            )
        workflow.dag_instance()
        assert mock_dag_cls.call_args.kwargs["schedule"] == "0 6 * * *"

    def test_validation_dag_has_cluster_validation_tag(self, _dag_instance_mocks):
        mock_dag_cls = _dag_instance_mocks
        with mock.patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.PROD}):
            workflow = BaseWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={},
                cluster_args={},
                is_validation=True,
            )
        workflow.dag_instance()
        tags = mock_dag_cls.call_args.kwargs["tags"]
        assert "cluster_validation" in tags

    def test_validation_check_include_sync_hive_tasks_returns_false(self):
        table_attributes = mock.MagicMock()
        table_attributes.table_customization = {"has_hive_sync": True}
        with mock.patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.PROD}):
            workflow = BaseWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={"has_hive_sync": True},
                cluster_args={},
                is_validation=True,
            )
        assert workflow._check_include_sync_hive_tasks(table_attributes) is False

    def test_prod_check_include_sync_hive_tasks_respects_config(self):
        table_attributes = mock.MagicMock()
        table_attributes.table_customization = {}
        with mock.patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.PROD}):
            workflow = BaseWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={"has_hive_sync": True},
                cluster_args={},
                is_validation=False,
            )
        assert workflow._check_include_sync_hive_tasks(table_attributes) is True

    def test_prod_dag_does_not_have_cluster_validation_tag(self, _dag_instance_mocks):
        mock_dag_cls = _dag_instance_mocks
        with mock.patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.PROD}):
            workflow = BaseWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={},
                cluster_args={},
                is_validation=False,
            )
        workflow.dag_instance()
        tags = mock_dag_cls.call_args.kwargs["tags"]
        assert tags is None or "cluster_validation" not in (tags or [])

    def test_validation_skips_optimize_task_creation(self):
        """optimize_delta_table_task_creator.create_task must not be called on validation DAGs."""

        class _Task:
            def __rshift__(self, other):
                return other

            def set_downstream(self, other):
                pass

        with mock.patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.PROD}):
            workflow = EnrichQueryDeltaWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={"type": "query_delta", "layer": "enrich"},
                cluster_args={"type": "consolidation_s_general_single_node_cluster"},
                dataset_dependencies=None,
                is_validation=True,
                validation_config={
                    "cluster": {"type": "consolidation_s_general_single_node_cluster"}
                },
            )

        from bietlejuice.base.airflow.task_creators.table_attributes import (
            TableAttributes,
        )

        table = mock.MagicMock(spec=TableAttributes)
        table.table_name = "my_table"
        table.layer = LayerEnum.ENRICH
        table.has_custom_spark_job = False
        table.table_customization = {}

        mock_optimize_creator = mock.MagicMock()
        mock_exec_creator = mock.MagicMock(return_value=_Task())
        mock_dummy_creator = mock.MagicMock(return_value=_Task())

        workflow.optimize_delta_table_task_creator = mock_optimize_creator
        workflow.execute_job_cluster_task_creator = mock_exec_creator
        workflow.dummy_job_cluster_finished_task_creator = mock_dummy_creator
        workflow.load_query_task_creator = mock.MagicMock(return_value=_Task())
        workflow.load_custom_task_creator = mock.MagicMock(return_value=_Task())
        workflow.skip_run_task_creator = mock.MagicMock(return_value=_Task())

        dummy_terminate = _Task()

        with (
            mock.patch(
                "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_query_delta_workflow.get_job_cluster_completion_sink",
                return_value=_Task(),
            ),
            mock.patch(
                "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_query_delta_workflow.attach_emr_job_cluster_finished_work_prerequisites"
            ),
            mock.patch.object(
                workflow, "_check_include_data_quality_task", return_value=False
            ),
            mock.patch.object(
                workflow, "_check_include_sync_hive_tasks", return_value=False
            ),
        ):
            workflow._create_all_tasks_for_cluster(
                cluster_tables=[table],
                execute_job_cluster_local_id=1,
                dummy_terminate_job_cluster_task=dummy_terminate,
                dag_execution_context=mock.MagicMock(),
            )

        mock_optimize_creator.create_task.assert_not_called()

    def test_validation_skips_data_quality_task_creation(self):
        """data_quality_tests_task_creator.create_task must not be called on validation DAGs."""

        class _Task:
            def __rshift__(self, other):
                return other

            def set_downstream(self, other):
                pass

        with mock.patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.PROD}):
            workflow = EnrichQueryDeltaWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={"type": "query_delta", "layer": "enrich"},
                cluster_args={"type": "consolidation_s_general_single_node_cluster"},
                dataset_dependencies=None,
                is_validation=True,
                validation_config={
                    "cluster": {"type": "consolidation_s_general_single_node_cluster"}
                },
            )

        from bietlejuice.base.airflow.task_creators.table_attributes import (
            TableAttributes,
        )

        table = mock.MagicMock(spec=TableAttributes)
        table.table_name = "my_table"
        table.layer = LayerEnum.ENRICH
        table.has_custom_spark_job = False
        table.table_customization = {}

        mock_dq_creator = mock.MagicMock()
        mock_optimize_creator = mock.MagicMock(return_value=_Task())
        mock_exec_creator = mock.MagicMock(return_value=_Task())
        mock_dummy_creator = mock.MagicMock(return_value=_Task())

        workflow.data_quality_tests_task_creator = mock_dq_creator
        workflow.optimize_delta_table_task_creator = mock_optimize_creator
        workflow.execute_job_cluster_task_creator = mock_exec_creator
        workflow.dummy_job_cluster_finished_task_creator = mock_dummy_creator
        workflow.load_query_task_creator = mock.MagicMock(return_value=_Task())
        workflow.load_custom_task_creator = mock.MagicMock(return_value=_Task())
        workflow.skip_run_task_creator = mock.MagicMock(return_value=_Task())

        dummy_terminate = _Task()

        with (
            mock.patch(
                "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_query_delta_workflow.get_job_cluster_completion_sink",
                return_value=_Task(),
            ),
            mock.patch(
                "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_query_delta_workflow.attach_emr_job_cluster_finished_work_prerequisites"
            ),
            mock.patch.object(
                workflow, "_check_include_sync_hive_tasks", return_value=False
            ),
        ):
            workflow._create_all_tasks_for_cluster(
                cluster_tables=[table],
                execute_job_cluster_local_id=1,
                dummy_terminate_job_cluster_task=dummy_terminate,
                dag_execution_context=mock.MagicMock(),
            )

        mock_dq_creator.create_task.assert_not_called()

    def test_prod_creates_optimize_task(self):
        """optimize_delta_table_task_creator.create_task must be called on prod DAGs."""

        class _Task:
            def __rshift__(self, other):
                return other

            def set_downstream(self, other):
                pass

        with mock.patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.PROD}):
            workflow = EnrichQueryDeltaWorkflow(
                dag_args={"name": "pilot", "owner": "Data Engineering"},
                workflow_args={"type": "query_delta", "layer": "enrich"},
                cluster_args={"type": "databricks_16_4_med_general_cluster"},
                dataset_dependencies=None,
                is_validation=False,
            )

        from bietlejuice.base.airflow.task_creators.table_attributes import (
            TableAttributes,
        )

        table = mock.MagicMock(spec=TableAttributes)
        table.table_name = "my_table"
        table.layer = LayerEnum.ENRICH
        table.has_custom_spark_job = False
        table.table_customization = {}

        mock_optimize_creator = mock.MagicMock(return_value=_Task())

        workflow.optimize_delta_table_task_creator = mock_optimize_creator
        workflow.execute_job_cluster_task_creator = mock.MagicMock(return_value=_Task())
        workflow.dummy_job_cluster_finished_task_creator = mock.MagicMock(
            return_value=_Task()
        )
        workflow.load_query_task_creator = mock.MagicMock(return_value=_Task())
        workflow.load_custom_task_creator = mock.MagicMock(return_value=_Task())
        workflow.skip_run_task_creator = mock.MagicMock(return_value=_Task())

        dummy_terminate = _Task()

        with (
            mock.patch(
                "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_query_delta_workflow.get_job_cluster_completion_sink",
                return_value=_Task(),
            ),
            mock.patch(
                "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_query_delta_workflow.attach_emr_job_cluster_finished_work_prerequisites"
            ),
            mock.patch.object(
                workflow, "_check_include_data_quality_task", return_value=False
            ),
            mock.patch.object(
                workflow, "_check_include_sync_hive_tasks", return_value=False
            ),
        ):
            workflow._create_all_tasks_for_cluster(
                cluster_tables=[table],
                execute_job_cluster_local_id=1,
                dummy_terminate_job_cluster_task=dummy_terminate,
                dag_execution_context=mock.MagicMock(),
            )

        mock_optimize_creator.create_task.assert_called_once()
