from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest

from bietlejuice.base.incident_context.databricks.databricks_metadata_service import (
    DatabricksIncidentContext,
    DatabricksMetadataService,
)
from bietlejuice.base.incident_context.databricks.databricks_run_error_service import (
    DEFAULT_ERROR_MESSAGE,
)


class TestDatabricksIncidentContext:
    def test_defaults(self):
        ctx = DatabricksIncidentContext()
        assert ctx.exception == DEFAULT_ERROR_MESSAGE
        assert ctx.log_destination is None
        assert ctx.databricks_run_url is None

    def test_custom_values(self):
        ctx = DatabricksIncidentContext(
            exception="boom",
            log_destination="s3://logs",
            databricks_run_url="https://dbc/runs/1",
        )
        assert ctx.exception == "boom"
        assert ctx.log_destination == "s3://logs"
        assert ctx.databricks_run_url == "https://dbc/runs/1"


class TestExtractRunIdFromUrl:
    def test_extracts_from_valid_url(self):
        run_id = DatabricksMetadataService._extract_run_id_from_url(
            url="https://dbc-xxx.cloud.databricks.com/jobs/123/runs/456",
            dag_id="test",
        )
        assert run_id == "456"

    def test_strips_trailing_slash(self):
        run_id = DatabricksMetadataService._extract_run_id_from_url(
            url="https://dbc-xxx.cloud.databricks.com/jobs/123/runs/456/",
            dag_id="test",
        )
        assert run_id == "456"

    def test_raises_on_none_url(self):
        with pytest.raises(Exception):
            DatabricksMetadataService._extract_run_id_from_url(url=None, dag_id="test")


class TestFromAirflowContext:
    @patch(
        "bietlejuice.base.incident_context.databricks.databricks_metadata_service.QuintoAndarDatabricksHook"
    )
    def test_creates_service_from_context(self, mock_hook_cls):
        context = {
            "dag_run": SimpleNamespace(dag_id="bietlejuice.my_dag"),
            "task_instance": MagicMock(
                xcom_pull=MagicMock(
                    return_value="https://dbc-xxx.cloud.databricks.com/jobs/1/runs/99"
                )
            ),
        }

        service = DatabricksMetadataService.from_airflow_context(
            context, databricks_conn_id="test_conn"
        )

        assert service.dag_id == "bietlejuice.my_dag"
        assert service.databricks_run_id == "99"
        assert (
            service.databricks_run_url
            == "https://dbc-xxx.cloud.databricks.com/jobs/1/runs/99"
        )
        mock_hook_cls.assert_called_once_with(databricks_conn_id="test_conn")


class TestGetDatabricksIncidentContext:
    @patch(
        "bietlejuice.base.incident_context.databricks.databricks_metadata_service.QuintoAndarDatabricksHook"
    )
    @patch(
        "bietlejuice.base.incident_context.databricks.databricks_metadata_service.DatabricksClusterLogService"
    )
    @patch(
        "bietlejuice.base.incident_context.databricks.databricks_metadata_service.DatabricksRunErrorService"
    )
    def test_returns_full_context(self, mock_error_cls, mock_log_cls, mock_hook_cls):
        mock_hook = mock_hook_cls.return_value
        mock_hook.get_job_run.return_value = {"run_id": "99", "tasks": []}

        mock_error_cls.return_value.get_databricks_run_error.return_value = (
            "Task 'load': OOM"
        )
        mock_log_cls.return_value.get_cluster_log_location.return_value = (
            "s3://logs/cluster-1"
        )

        service = DatabricksMetadataService(
            dag_id="test_dag",
            databricks_run_url="https://dbc/runs/99",
            databricks_run_id="99",
            databricks_conn_id="test_conn",
        )

        result = service.get_databricks_incident_context()

        assert isinstance(result, DatabricksIncidentContext)
        assert result.exception == "Task 'load': OOM"
        assert result.log_destination == "s3://logs/cluster-1"
        assert result.databricks_run_url == "https://dbc/runs/99"
