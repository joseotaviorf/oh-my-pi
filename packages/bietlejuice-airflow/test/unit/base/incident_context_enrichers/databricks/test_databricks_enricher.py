"""Tests for DatabricksIncidentContextEnricher."""

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from bietlejuice.base.incident_context_enrichers.databricks.databricks_enricher import (
    DatabricksIncidentContextEnricher,
)
from bietlejuice.base.incident_context_enrichers.databricks.databricks_metadata_service import (
    DatabricksIncidentContext,
)


class TestDatabricksIncidentContextEnricher:
    def test_enrich_adds_context_when_service_returns_data(self):
        """When Databricks context is available, enrich adds keys and description lines."""
        enricher = DatabricksIncidentContextEnricher(databricks_conn_id="test_conn")
        context = MagicMock()
        extra_properties = {"DAG": "my_dag"}
        description = "Original description"

        databricks_context = DatabricksIncidentContext(
            exception="SparkException: OOM",
            log_destination="s3://logs/cluster-123",
            databricks_run_url="https://dbc/runs/456",
        )

        with patch(
            "bietlejuice.base.incident_context_enrichers.databricks.databricks_enricher.DatabricksMetadataService.from_airflow_context"
        ) as mock_from_ctx:
            mock_service = MagicMock()
            mock_service.get_databricks_incident_context.return_value = (
                databricks_context
            )
            mock_from_ctx.return_value = mock_service

            out_extra, out_desc = enricher.enrich(
                context, extra_properties, description
            )

        assert out_extra["DatabricksError"] == "SparkException: OOM"
        assert out_extra["DatabricksRunURL"] == "https://dbc/runs/456"
        assert out_extra["ClusterLogLocation"] == "s3://logs/cluster-123"
        assert out_extra["DAG"] == "my_dag"
        assert "SparkException: OOM" in out_desc
        assert "https://dbc/runs/456" in out_desc
        assert "s3://logs/cluster-123" in out_desc
        assert "Original description" in out_desc
        mock_from_ctx.assert_called_once_with(context, "test_conn")

    def test_enrich_returns_unchanged_when_service_raises(self):
        """When DatabricksMetadataService raises, enrich returns payload unchanged."""
        enricher = DatabricksIncidentContextEnricher(databricks_conn_id="test_conn")
        context = MagicMock()
        extra_properties = {"DAG": "my_dag"}
        description = "Original description"

        with patch(
            "bietlejuice.base.incident_context_enrichers.databricks.databricks_enricher.DatabricksMetadataService.from_airflow_context",
            side_effect=ValueError("no run_page_url in XCom"),
        ):
            out_extra, out_desc = enricher.enrich(
                context, extra_properties, description
            )

        assert out_extra == extra_properties
        assert out_desc == description
        assert "DatabricksError" not in out_extra
        assert "DatabricksRunURL" not in out_extra
        assert "ClusterLogLocation" not in out_extra

    def test_enrich_returns_unchanged_when_context_is_none(self):
        """When get_databricks_incident_context returns None, enrich returns payload unchanged."""
        enricher = DatabricksIncidentContextEnricher(databricks_conn_id="test_conn")
        context = MagicMock()
        extra_properties = {"DAG": "my_dag"}
        description = "Original description"

        with patch(
            "bietlejuice.base.incident_context_enrichers.databricks.databricks_enricher.DatabricksMetadataService.from_airflow_context"
        ) as mock_from_ctx:
            mock_service = MagicMock()
            mock_service.get_databricks_incident_context.return_value = None
            mock_from_ctx.return_value = mock_service

            out_extra, out_desc = enricher.enrich(
                context, extra_properties, description
            )

        assert out_extra == extra_properties
        assert out_desc == description
        assert "DatabricksError" not in out_extra

    def test_enrich_skips_optional_lines_when_url_or_log_missing(self):
        """Description only includes Error line when run URL and log destination are None."""
        enricher = DatabricksIncidentContextEnricher(databricks_conn_id="test_conn")
        context = MagicMock()
        extra_properties = {}
        description = "Base"

        databricks_context = DatabricksIncidentContext(
            exception="Error message",
            log_destination=None,
            databricks_run_url=None,
        )

        with patch(
            "bietlejuice.base.incident_context_enrichers.databricks.databricks_enricher.DatabricksMetadataService.from_airflow_context"
        ) as mock_from_ctx:
            mock_service = MagicMock()
            mock_service.get_databricks_incident_context.return_value = (
                databricks_context
            )
            mock_from_ctx.return_value = mock_service

            out_extra, out_desc = enricher.enrich(
                context, extra_properties, description
            )

        assert "Error: Error message" in out_desc
        assert "Run URL:" not in out_desc
        assert "Cluster Logs:" not in out_desc

    def test_enrich_skips_silently_when_task_has_no_run_page_url(self):
        enricher = DatabricksIncidentContextEnricher()
        context = {
            "dag_run": SimpleNamespace(dag_id="bietlejuice.emr_dag"),
            "task_instance": MagicMock(xcom_pull=MagicMock(return_value=None)),
        }

        with patch(
            "bietlejuice.base.incident_context_enrichers.databricks.databricks_enricher.logger"
        ) as logger:
            result = enricher.enrich(context, {"DAG": "emr_dag"}, "Original")

        assert result == ({"DAG": "emr_dag"}, "Original")
        logger.warning.assert_not_called()
