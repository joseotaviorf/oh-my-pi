"""Prod conf environment for cluster validation tests (opt-in via pytest_plugins)."""

import pytest

from bietlejuice.services.configuration_service import ConfigurationService


@pytest.fixture(autouse=True)
def _prod_environment(monkeypatch):
    """Match extract/validate CI: consolidation presets come from prod_conf."""
    monkeypatch.setenv("ENVIRONMENT", "prod")
    ConfigurationService._instance_cache.clear()
    yield
