"""Databricks incident context enricher for JiraOps alerts."""

import logging
from typing import Any, Tuple

from bietlejuice.base.incident_context_enrichers.databricks.databricks_metadata_service import (
    DatabricksMetadataService,
)
from bietlejuice.base.incident_context_enrichers.enricher import IncidentContextEnricher

logger = logging.getLogger(__name__)


class DatabricksIncidentContextEnricher(IncidentContextEnricher):
    """Enricher that adds Databricks run error, run URL, and cluster log location to alerts."""

    def __init__(self, databricks_conn_id: str = "databricks_default"):
        self.databricks_conn_id = databricks_conn_id

    def enrich(
        self,
        context: Any,
        extra_properties: dict,
        description: str,
    ) -> Tuple[dict, str]:
        """Add Databricks run context to extra_properties and description."""
        try:
            service = DatabricksMetadataService.from_airflow_context(
                context, self.databricks_conn_id
            )
            databricks_context = (
                service.get_databricks_incident_context() if service else None
            )
        except Exception as err:
            logger.warning(
                "Could not retrieve Databricks context for alert enrichment: %s",
                err,
                exc_info=True,
            )
            return extra_properties, description

        if not databricks_context:
            return extra_properties, description

        extra_properties["DatabricksError"] = databricks_context.exception
        extra_properties["DatabricksRunURL"] = databricks_context.databricks_run_url
        extra_properties["ClusterLogLocation"] = databricks_context.log_destination
        description += f"\nError: {databricks_context.exception}"
        if databricks_context.databricks_run_url:
            description += f"\nRun URL: {databricks_context.databricks_run_url}"
        if databricks_context.log_destination:
            description += f"\nCluster Logs: {databricks_context.log_destination}"
        return extra_properties, description
