from unittest.mock import MagicMock, patch

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_gsheets_workflow import (
    RawGsheetsWorkflow,
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
