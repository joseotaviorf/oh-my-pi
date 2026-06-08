import logging
from typing import Any, Tuple

from bietlejuice.base.incident_context_enrichers.enricher import IncidentContextEnricher
from bietlejuice.base.incident_context_enrichers.jira.jira_incident_owner_service import (
    JiraIncidentOwnerService,
)

logger = logging.getLogger(__name__)


class JiraEnricher(IncidentContextEnricher):
    """Optional enricher: syncs Jira Incident Owner field options before the alert is sent.

    Does not add keys to ``extra_properties``; failures are logged and the alert proceeds.
    """

    def enrich(
        self,
        context: Any,
        extra_properties: dict,
        description: str,
    ) -> Tuple[dict, str]:
        """Sync Jira incident owner select options (best-effort)."""
        try:
            jira_incident_owner_service = JiraIncidentOwnerService()
            jira_incident_owner_service.sync_incident_owner_options()
        except Exception as err:
            logger.warning(
                "Could not sync Jira incident owner options: %s",
                err,
                exc_info=True,
            )
        return extra_properties, description
