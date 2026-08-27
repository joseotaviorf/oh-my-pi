"""Unit tests for MetricQueryWorkflow (metric layer query workflow)."""

from datetime import datetime
from unittest.mock import MagicMock, patch

from airflow.models import DAG

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.metric_query_workflow import (
    MetricQueryWorkflow,
)
from bietlejuice.base.pipeline.environment_enum import EnvironmentEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TestMetricQueryWorkflow:
    @staticmethod
    def _mock_dag():
        return DAG(
            dag_id="bietlejuice.metric_growth__demand",
            start_date=datetime(2024, 1, 1),
            schedule=None,
        )

    def _metric_config(self, key):
        return {
            "metrics_bucket": "metrics-bucket",
            "databricks_bietlejuice_repo_path": "/repo",
            "doc_md_chart_url": "https://charts.example.com",
        }[key]

    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.metric_query_workflow.DatasetAdder.attach_reprocessing_guard"
    )
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.metric_query_workflow.DatalakeTaskGroup"
    )
    @patch.object(MetricQueryWorkflow, "dag_instance")
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ConfigurationService"
    )
    def test_build_dag_databricks_uses_task_submission_engine(
        self,
        mock_config_service,
        mock_dag_instance,
        mock_task_group_cls,
        _mock_reprocessing_guard,
    ):
        mock_config_service.return_value.get_config.side_effect = self._metric_config
        mock_dag_instance.return_value = self._mock_dag()

        mock_engine = MagicMock()
        mock_engine.create_execute_cluster_task.return_value = MagicMock(
            task_id="create-cluster"
        )
        mock_engine.create_databricks_terminate_cluster_task.return_value = MagicMock(
            task_id="terminate-cluster"
        )
        mock_ctx = MagicMock(
            job_cluster_engine=mock_engine,
            use_airflow_emr=False,
            databricks_conn_id="databricks_new",
        )

        mock_task_group = MagicMock()
        mock_task_group.build_task_group_from_sql_files.return_value = {
            "growth_demand_performance_daily": (
                MagicMock(task_id="load-metric-growth-growth_demand_performance_daily"),
            )
        }
        mock_task_group_cls.return_value = mock_task_group
        mock_task_group_cls.all_first_tasks.return_value = [
            MagicMock(task_id="load-metric-growth-growth_demand_performance_daily")
        ]
        mock_task_group_cls.all_last_tasks.return_value = [
            MagicMock(task_id="load-metric-growth-growth_demand_performance_daily")
        ]
        mock_task_group_cls.all_independent_tasks.return_value = []

        workflow = MetricQueryWorkflow(
            dag_args={"name": "metric_growth__demand", "owner": "Data Growth"},
            workflow_args={
                "type": "query",
                "layer": LayerEnum.METRIC.value,
                "default_extraction_type": "incremental",
            },
            cluster_args={
                "type": "consolidation_s_general_cluster",
                "databricks_conn_id": "databricks_new",
            },
        )

        with patch.object(
            workflow, "_get_dag_execution_context", return_value=mock_ctx
        ) as mock_get_ctx:
            workflow.build_dag()

        mock_get_ctx.assert_called_once()
        assert (
            mock_get_ctx.call_args.kwargs["databricks_submission_mode"]
            == "task_submission"
        )
        mock_engine.create_execute_cluster_task.assert_called_once()
        mock_engine.create_databricks_terminate_cluster_task.assert_called_once()
        mock_task_group_cls.assert_called_once()
        assert mock_task_group_cls.call_args.kwargs["job_cluster_engine"] is mock_engine

    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.metric_query_workflow.DatasetAdder.attach_reprocessing_guard"
    )
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.metric_query_workflow.DatalakeTaskGroup"
    )
    @patch.object(MetricQueryWorkflow, "dag_instance")
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ConfigurationService"
    )
    def test_build_dag_defaults_databricks_conn_id(
        self,
        mock_config_service,
        mock_dag_instance,
        mock_task_group_cls,
        _mock_reprocessing_guard,
    ):
        mock_config_service.return_value.get_config.side_effect = self._metric_config
        mock_dag_instance.return_value = self._mock_dag()
        mock_engine = MagicMock()
        mock_engine.create_execute_cluster_task.return_value = MagicMock(
            task_id="create-cluster"
        )
        mock_engine.create_databricks_terminate_cluster_task.return_value = MagicMock(
            task_id="terminate-cluster"
        )
        mock_ctx = MagicMock(
            job_cluster_engine=mock_engine,
            use_airflow_emr=False,
            databricks_conn_id="databricks_default",
        )
        mock_task_group = MagicMock()
        mock_task_group.build_task_group_from_sql_files.return_value = {}
        mock_task_group_cls.return_value = mock_task_group
        mock_task_group_cls.all_first_tasks.return_value = []
        mock_task_group_cls.all_last_tasks.return_value = []
        mock_task_group_cls.all_independent_tasks.return_value = []

        workflow = MetricQueryWorkflow(
            dag_args={"name": "metric_growth__demand", "owner": "Data Growth"},
            workflow_args={
                "type": "query",
                "layer": LayerEnum.METRIC.value,
            },
            cluster_args={"type": "consolidation_s_general_cluster"},
        )

        with patch.object(
            workflow, "_get_dag_execution_context", return_value=mock_ctx
        ):
            workflow.build_dag()

        assert workflow.cluster_args["databricks_conn_id"] == "databricks_default"

    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.metric_query_workflow.attach_emr_job_cluster_finished_work_prerequisites"
    )
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.metric_query_workflow.attach_emr_terminate_cluster_work_prerequisites"
    )
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.metric_query_workflow.get_job_cluster_completion_sink"
    )
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.metric_query_workflow.DatasetAdder.attach_reprocessing_guard"
    )
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.metric_query_workflow.DatalakeTaskGroup"
    )
    @patch.object(MetricQueryWorkflow, "dag_instance")
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ConfigurationService"
    )
    def test_build_dag_emr_validation_wires_terminate_sink(
        self,
        mock_config_service,
        mock_dag_instance,
        mock_task_group_cls,
        _mock_reprocessing_guard,
        mock_completion_sink,
        mock_attach_emr,
        mock_attach_finished,
    ):
        mock_config_service.return_value.get_config.side_effect = self._metric_config
        mock_dag_instance.return_value = self._mock_dag()

        create_cluster = MagicMock(task_id="execute-job-cluster")
        terminate_sink = MagicMock(task_id="terminate-emr-cluster")
        mock_engine = MagicMock()
        mock_engine.create_execute_cluster_task.return_value = create_cluster
        mock_completion_sink.return_value = terminate_sink

        mock_ctx = MagicMock(
            job_cluster_engine=mock_engine,
            use_airflow_emr=True,
            databricks_conn_id="databricks_new",
        )

        mock_task_group = MagicMock()
        mock_task_group.build_task_group_from_sql_files.return_value = {
            "growth_demand_performance_daily": (
                MagicMock(task_id="load-metric-growth-growth_demand_performance_daily"),
            )
        }
        mock_task_group_cls.return_value = mock_task_group
        mock_task_group_cls.all_first_tasks.return_value = [
            MagicMock(task_id="load-metric-growth-growth_demand_performance_daily")
        ]
        mock_task_group_cls.all_last_tasks.return_value = [
            MagicMock(task_id="load-metric-growth-growth_demand_performance_daily")
        ]
        mock_task_group_cls.all_independent_tasks.return_value = []

        workflow = MetricQueryWorkflow(
            dag_args={"name": "metric_growth__demand", "owner": "Data Growth"},
            workflow_args={
                "type": "query",
                "layer": LayerEnum.METRIC.value,
                "default_extraction_type": "incremental",
            },
            cluster_args={
                "type": "emr_7_12_consolidation_s_general_fleet_cluster",
            },
            is_validation=True,
            validation_config={
                "cluster": {
                    "type": "emr_7_12_consolidation_s_general_fleet_cluster",
                }
            },
        )

        with patch.object(
            workflow, "_get_dag_execution_context", return_value=mock_ctx
        ):
            workflow.build_dag()

        mock_completion_sink.assert_called_once()
        job_cluster_finished_task = mock_completion_sink.call_args.args[2]
        assert job_cluster_finished_task.task_id == "job-cluster-finished"
        mock_attach_emr.assert_called_once_with(
            mock_ctx,
            terminate_sink,
            execute_job_cluster_task=create_cluster,
            job_cluster_finished_task=job_cluster_finished_task,
        )
        mock_attach_finished.assert_called_once_with(
            mock_ctx,
            job_cluster_finished_task,
            cluster_completion_sink=terminate_sink,
        )
        mock_engine.create_databricks_terminate_cluster_task.assert_not_called()

    @patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.PROD})
    def test_validation_workflow_builds_with_emr_cluster_preset(self):
        """Integration: EMR validation cluster must not call Databricks env-var helpers."""
        from bietlejuice.base.airflow.dag_builders.main_builder.factories.factory_dispatcher import (
            FactoryDispatcher,
        )
        from bietlejuice.base.validation.cluster_args import (
            merge_validation_cluster_args,
        )

        declaration_cluster = {
            "type": "consolidation_s_general_cluster",
            "access_control_list": {"group_name": "analytics-engineers"},
            "databricks_conn_id": "databricks_new",
        }
        validation = {
            "cluster": {
                "type": "emr_7_12_consolidation_s_general_fleet_cluster",
                "custom_configurations": {
                    "task_nodes": {"target_spot": 1},
                },
            }
        }
        merged_cluster = merge_validation_cluster_args(
            declaration_cluster, validation["cluster"]
        )

        factory = FactoryDispatcher(layer=LayerEnum.METRIC).get_factory(
            dag_args={"name": "metric_growth__demand", "owner": "Data Growth"},
            workflow_args={
                "type": "query",
                "layer": LayerEnum.METRIC.value,
                "default_extraction_type": "incremental",
            },
            cluster_args=merged_cluster,
            dataset_dependencies=None,
            is_validation=True,
            validation_config=validation,
        )

        with patch(
            "bietlejuice.base.airflow.dag_builders.main_builder.workflows.metric_query_workflow.DatasetAdder.attach_reprocessing_guard"
        ):
            dag = factory.get_workflow().build_dag()

        assert dag.dag_id == "bietlejuice.metric_growth__demand__validation"
        task_ids = {task.task_id for task in dag.tasks}
        assert "execute-job-cluster" in task_ids
        assert "create-cluster" not in task_ids
