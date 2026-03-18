"""Base type for enrichers that add context to JiraOps alerts."""

from abc import ABC, abstractmethod
from typing import Any, Tuple


class IncidentContextEnricher(ABC):
    """Base class for enrichers that add incident context to alert payloads."""

    @abstractmethod
    def enrich(
        self,
        context: Any,
        extra_properties: dict,
        description: str,
    ) -> Tuple[dict, str]:
        """Enrich alert extra_properties and description with additional context.

        Args:
            context: Airflow context (or similar) for the failure.
            extra_properties: Current dict of extra properties for the alert.
            description: Current alert description text.

        Returns:
            Tuple of (updated extra_properties, updated description).
        """
        pass
