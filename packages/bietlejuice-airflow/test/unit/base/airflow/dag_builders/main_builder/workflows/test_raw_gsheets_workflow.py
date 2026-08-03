from unittest.mock import MagicMock, patch

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
