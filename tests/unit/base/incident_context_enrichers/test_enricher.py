"""Tests for IncidentContextEnricher base and dummy enricher."""

import pytest
from bietlejuice.base.incident_context_enrichers.enricher import IncidentContextEnricher


class DummyEnricher(IncidentContextEnricher):
    """Dummy enricher for tests: adds a fixed key and suffix."""

    def __init__(
        self, key: str = "DummyKey", value: str = "dummy_value", suffix: str = ""
    ):
        self.key = key
        self.value = value
        self.suffix = suffix or f"\nEnriched by {key}: {value}"

    def enrich(self, context, extra_properties: dict, description: str):
        extra_properties = dict(extra_properties)
        extra_properties[self.key] = self.value
        return extra_properties, description + self.suffix


def test_dummy_enricher_implements_enrich():
    """DummyEnricher implements enrich and returns (dict, str)."""
    enricher = DummyEnricher()
    extra = {"DAG": "test_dag"}
    desc = "Original description"
    out_extra, out_desc = enricher.enrich(None, extra, desc)
    assert out_extra["DummyKey"] == "dummy_value"
    assert out_extra["DAG"] == "test_dag"
    assert "Enriched by DummyKey" in out_desc
    assert out_desc.endswith("dummy_value")


def test_dummy_enricher_does_not_mutate_input():
    """enrich returns new dict; input extra_properties unchanged."""
    enricher = DummyEnricher(key="K", value="V")
    extra = {"A": 1}
    desc = "Desc"
    out_extra, _ = enricher.enrich(None, extra, desc)
    assert extra == {"A": 1}
    assert out_extra == {"A": 1, "K": "V"}


def test_incident_context_enricher_is_abstract():
    """IncidentContextEnricher cannot be instantiated directly."""
    with pytest.raises(TypeError):
        IncidentContextEnricher()
