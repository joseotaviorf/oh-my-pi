from datetime import datetime
from unittest.mock import MagicMock, patch

from airflow import DAG

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_gsheets_workflow import (
    RawGsheetsWorkflow,
)


def _build_workflow(workflow_args=None):
    with patch.object(RawGsheetsWorkflow, "dag_instance", return_value=MagicMock()):
        with patch(
            "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ConfigurationService"
        ) as mock_config_service:
            mock_config_service.return_value.get_config.side_effect = lambda key: {
                "datalake_bucket": "test-bucket",
                "artifacts_bucket": "s3://artifacts.s3.data.quintoandar.com.br",
                "databricks_bietlejuice_repo_path": "/repo",
            }[key]
            return RawGsheetsWorkflow(
                dag_args={"name": "gsheets_test", "owner": "Data Engineering"},
                workflow_args=workflow_args or {},
                cluster_args={"type": "databricks_16_4_med_general_fleet"},
            )


class TestRawGsheetsWorkflowDocumentation:
    @patch.object(RawGsheetsWorkflow, "dag_instance", return_value=MagicMock())
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ConfigurationService"
    )
    def test_init_preserves_class_default_dag_purpose(
        self, mock_config_service, _mock_dag_instance
    ):
        mock_config_service.return_value.get_config.side_effect = lambda key: {
            "datalake_bucket": "test-bucket",
            "artifacts_bucket": "s3://artifacts.s3.data.quintoandar.com.br",
            "databricks_bietlejuice_repo_path": "/repo",
        }[key]
        original_purpose = RawGsheetsWorkflow.DEFAULT_DAG_DOCUMENTATION["dag_purpose"]

        workflow = RawGsheetsWorkflow(
            dag_args={"name": "gsheets_test", "owner": "Data Engineering"},
            workflow_args={},
            cluster_args={"type": "databricks_16_4_med_general_fleet"},
        )

        assert (
            RawGsheetsWorkflow.DEFAULT_DAG_DOCUMENTATION["dag_purpose"]
            == original_purpose
        )
        assert "{dag_context}" in original_purpose
        assert "test Context" in workflow.dag_args["documentation"]["dag_purpose"]


class TestRawGsheetsWorkflowAlertChannel:
    def test_init_stores_alert_channel_from_workflow_args(self):
        workflow = _build_workflow(workflow_args={"alert_channel": "PEOPLE_ALERTS"})
        assert workflow.alert_channel == "PEOPLE_ALERTS"

    def test_init_alert_channel_defaults_to_none(self):
        workflow = _build_workflow(workflow_args={})
        assert workflow.alert_channel is None

    def test_set_raw_tasks_passes_alert_channel_cli_flag(self):
        workflow = _build_workflow(workflow_args={"alert_channel": "PEOPLE_ALERTS"})
        task_group = MagicMock()
        task_group.build_raw_task_group_for_single_table.return_value = MagicMock()
        google_files = [
            (
                "raw_talent_mapping",
                {
                    "clean_table_name": "talent_mapping_base",
                    "sheet_id": "sheet-1",
                    "sheet_name": "Sheet1",
                    "sheet_context": "people",
                },
            )
        ]

        workflow._set_raw_tasks(
            google_files=google_files,
            dag_name="gsheets_test",
            schema="gsheets_people",
            task_pool="gsheets_pool",
            raw_spark_job_path="/repo/spark_jobs/base/load_gsheets_into_datalake.py",
            task_group=task_group,
        )

        kwargs = task_group.build_raw_task_group_for_single_table.call_args.kwargs
        extra_args = kwargs["raw_spark_job_extra_args"]
        assert "--alert-channel" in extra_args
        assert extra_args[extra_args.index("--alert-channel") + 1] == "PEOPLE_ALERTS"

    def test_set_raw_tasks_omits_alert_channel_when_not_configured(self):
        workflow = _build_workflow(workflow_args={})
        task_group = MagicMock()
        task_group.build_raw_task_group_for_single_table.return_value = MagicMock()
        google_files = [
            (
                "raw_talent_mapping",
                {
                    "clean_table_name": "talent_mapping_base",
                    "sheet_id": "sheet-1",
                    "sheet_name": "Sheet1",
                    "sheet_context": "people",
                },
            )
        ]

        workflow._set_raw_tasks(
            google_files=google_files,
            dag_name="gsheets_test",
            schema="gsheets_people",
            task_pool="gsheets_pool",
            raw_spark_job_path="/repo/spark_jobs/base/load_gsheets_into_datalake.py",
            task_group=task_group,
        )

        kwargs = task_group.build_raw_task_group_for_single_table.call_args.kwargs
        assert "--alert-channel" not in kwargs["raw_spark_job_extra_args"]


class TestRawGsheetsWorkflowEngineWiring:
    @staticmethod
    def _mock_dag():
        return DAG(
            dag_id="bietlejuice.gsheets_test",
            start_date=datetime(2024, 1, 1),
            schedule=None,
        )

    @patch.object(RawGsheetsWorkflow, "set_dependencies")
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_gsheets_workflow.TaskFlowHelper.chain_task_groups_via_common_table"
    )
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_gsheets_workflow.attach_emr_terminate_cluster_work_prerequisites"
    )
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_gsheets_workflow.get_job_cluster_completion_sink"
    )
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_gsheets_workflow.DatalakeTaskGroup"
    )
    @patch.object(RawGsheetsWorkflow, "dag_instance")
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ConfigurationService"
    )
    def test_build_dag_uses_task_submission_engine_on_databricks(
        self,
        mock_config_service,
        mock_dag_instance,
        mock_task_group_cls,
        _mock_completion_sink,
        _mock_attach_emr,
        _mock_chain_tables,
        _mock_set_dependencies,
    ):
        mock_config_service.return_value.get_config.side_effect = lambda key: {
            "datalake_bucket": "test-bucket",
            "artifacts_bucket": "s3://artifacts.s3.data.quintoandar.com.br",
            "databricks_bietlejuice_repo_path": "/repo",
            "doc_md_chart_url": "https://charts.example.com",
            "sheets_info": {
                "raw_sheet": {
                    "clean_table_name": "sheet_clean",
                    "sheet_id": "id-1",
                    "sheet_name": "Sheet1",
                }
            },
        }[key]

        mock_engine = MagicMock()
        mock_engine.create_execute_cluster_task.return_value = MagicMock(
            task_id="create-cluster"
        )
        mock_engine.create_spark_python_task.return_value = MagicMock(
            task_id="ingested-gsheets-id-info"
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
            "sheet_clean": (MagicMock(task_id="clean-sheet_clean"),)
        }
        mock_task_group.build_raw_task_group_for_single_table.return_value = (
            MagicMock(task_id="load-raw_sheet"),
        )
        mock_task_group_cls.return_value = mock_task_group
        mock_task_group_cls.first_tasks.side_effect = lambda tasks: [tasks[0]]
        mock_task_group_cls.all_last_tasks.return_value = [
            MagicMock(task_id="done-clean-sheet_clean")
        ]
        mock_task_group_cls.all_independent_tasks.return_value = []
        mock_task_group_cls.format_tasks_boundaries.side_effect = lambda first, last: (
            first[0],
            last[0],
        )

        mock_dag_instance.return_value = self._mock_dag()

        workflow = RawGsheetsWorkflow(
            dag_args={"name": "gsheets_test", "owner": "Data Engineering"},
            workflow_args={},
            cluster_args={"type": "databricks_16_4_med_general_fleet"},
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
        mock_engine.create_spark_python_task.assert_called_once()
        mock_engine.create_databricks_terminate_cluster_task.assert_called_once()
        mock_task_group_cls.assert_called_once()
        assert mock_task_group_cls.call_args.kwargs["job_cluster_engine"] is mock_engine

    @patch.object(RawGsheetsWorkflow, "set_dependencies")
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_gsheets_workflow.TaskFlowHelper.chain_task_groups_via_common_table"
    )
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_gsheets_workflow.attach_emr_job_cluster_finished_work_prerequisites"
    )
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_gsheets_workflow.attach_emr_terminate_cluster_work_prerequisites"
    )
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_gsheets_workflow.get_job_cluster_completion_sink"
    )
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_gsheets_workflow.DatalakeTaskGroup"
    )
    @patch.object(RawGsheetsWorkflow, "dag_instance")
    @patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ConfigurationService"
    )
    def test_build_dag_wires_emr_terminate_sink(
        self,
        mock_config_service,
        mock_dag_instance,
        mock_task_group_cls,
        mock_completion_sink,
        mock_attach_emr,
        mock_attach_finished,
        _mock_chain_tables,
        _mock_set_dependencies,
    ):
        mock_config_service.return_value.get_config.side_effect = lambda key: {
            "datalake_bucket": "test-bucket",
            "artifacts_bucket": "s3://artifacts.s3.data.quintoandar.com.br",
            "databricks_bietlejuice_repo_path": "/repo",
            "doc_md_chart_url": "https://charts.example.com",
            "sheets_info": {
                "raw_sheet": {
                    "clean_table_name": "sheet_clean",
                    "sheet_id": "id-1",
                    "sheet_name": "Sheet1",
                }
            },
        }[key]

        mock_dag_instance.return_value = self._mock_dag()

        create_cluster = MagicMock(task_id="execute-job-cluster")
        terminate_sink = MagicMock(task_id="terminate-emr-cluster")
        mock_engine = MagicMock()
        mock_engine.create_execute_cluster_task.return_value = create_cluster
        mock_engine.create_spark_python_task.return_value = MagicMock(
            task_id="ingested-gsheets-id-info"
        )
        mock_completion_sink.return_value = terminate_sink

        mock_ctx = MagicMock(
            job_cluster_engine=mock_engine,
            use_airflow_emr=True,
            databricks_conn_id="databricks_new",
        )

        mock_task_group = MagicMock()
        mock_task_group.build_task_group_from_sql_files.return_value = {
            "sheet_clean": (MagicMock(task_id="clean-sheet_clean"),)
        }
        mock_task_group.build_raw_task_group_for_single_table.return_value = (
            MagicMock(task_id="load-raw_sheet"),
        )
        mock_task_group_cls.return_value = mock_task_group
        mock_task_group_cls.first_tasks.side_effect = lambda tasks: [tasks[0]]
        mock_task_group_cls.all_last_tasks.return_value = [
            MagicMock(task_id="done-clean-sheet_clean")
        ]
        mock_task_group_cls.all_independent_tasks.return_value = []
        mock_task_group_cls.format_tasks_boundaries.side_effect = lambda first, last: (
            first[0],
            last[0],
        )

        workflow = RawGsheetsWorkflow(
            dag_args={"name": "gsheets_test", "owner": "Data Engineering"},
            workflow_args={},
            cluster_args={"type": "emr_7_12_consolidation_s_memory_fleet_cluster"},
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
