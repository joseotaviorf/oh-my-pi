from unittest.mock import MagicMock, patch

from bietlejuice.base.notification.reverse_bpo_summary_callback import (
    _extract_dag_name,
    reverse_bpo_export_summary_alert,
)

MODULE = "bietlejuice.base.notification.reverse_bpo_summary_callback"


class TestExtractDagName:
    def test_strips_bietlejuice_prefix(self):
        assert _extract_dag_name("bietlejuice.reverse_atento") == "reverse_atento"


class TestReverseBpoExportSummaryAlert:
    @patch(f"{MODULE}.GChatService.send_message", return_value=True)
    @patch(f"{MODULE}._delete_summary_markers")
    @patch(
        f"{MODULE}._resolve_webhook_url",
        return_value="https://chat.googleapis.com/webhook",
    )
    @patch(f"{MODULE}._list_saved_files_from_markers")
    @patch(f"{MODULE}._get_declaration_tables")
    @patch(f"{MODULE}.DAGYamlParser")
    @patch(f"{MODULE}.ConfigurationService")
    def test_sends_summary_for_saved_files(
        self,
        mock_config_service,
        mock_dag_yaml_parser,
        mock_get_declaration_tables,
        mock_list_saved_files,
        _mock_resolve_webhook,
        _mock_delete_markers,
        mock_send_message,
    ):
        mock_dag_yaml_parser.return_value.dag_declaration.return_value = {
            "workflow": {"gchat_export_summary": True}
        }
        mock_config_service.return_value.get_config.return_value = "5a-dataops-prod"
        mock_get_declaration_tables.return_value = [
            "backlog_metric",
            "cases_perspective",
        ]
        mock_list_saved_files.return_value = [
            "cases_perspective_2026_08_26.parquet",
            "backlog_metric_2026_08_26.parquet",
        ]

        context = {
            "dag": MagicMock(dag_id="bietlejuice.reverse_atento"),
            "dag_run": MagicMock(run_id="manual__2026-08-26"),
        }

        reverse_bpo_export_summary_alert(context)

        mock_send_message.assert_called_once()
        message = mock_send_message.call_args[0][0].content
        assert "reverse_atento" in message
        assert "✅ backlog_metric_2026_08_26.parquet" in message
        assert "✅ cases_perspective_2026_08_26.parquet" in message

    @patch(f"{MODULE}.GChatService.send_message")
    @patch(f"{MODULE}.DAGYamlParser")
    def test_skips_when_summary_flag_is_disabled(
        self, mock_dag_yaml_parser, mock_send_message
    ):
        mock_dag_yaml_parser.return_value.dag_declaration.return_value = {
            "workflow": {}
        }
        context = {
            "dag": MagicMock(dag_id="bietlejuice.reverse_atento"),
            "dag_run": MagicMock(run_id="manual__2026-08-26"),
        }

        reverse_bpo_export_summary_alert(context)

        mock_send_message.assert_not_called()


class TestReverseLoadAccessWorkflowSummaryCallback:
    @patch(
        "bietlejuice.base.notification.reverse_bpo_summary_callback.reverse_bpo_export_summary_alert"
    )
    def test_dag_instance_registers_summary_callback_when_enabled(self, mock_callback):
        from unittest.mock import MagicMock

        from pendulum import timezone

        from bietlejuice.base.airflow.dag_builders.main_builder.workflows.reverse_load_access_workflow import (
            ReverseLoadAccessWorkflow,
        )

        workflow = ReverseLoadAccessWorkflow.__new__(ReverseLoadAccessWorkflow)
        workflow.workflow_args = {"gchat_export_summary": True}
        workflow.dag_args = {"name": "reverse_aec", "owner": "owner"}
        workflow.dag_name = "reverse_aec"
        workflow.is_validation = False
        workflow.dataset_dependencies = []
        workflow.config_service = MagicMock()
        workflow.local_tz = timezone("America/Sao_Paulo")

        with patch.object(
            ReverseLoadAccessWorkflow.__bases__[0],
            "dag_instance",
            return_value=MagicMock(),
        ) as mock_super:
            workflow.dag_instance()

        assert mock_super.call_args.kwargs["on_success_callback"] is mock_callback
