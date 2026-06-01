"""Prod conf environment for cluster validation tests (opt-in via pytest_plugins)."""

import os

import pytest

from bietlejuice.services.configuration_service import ConfigurationService


@pytest.fixture(scope="session", autouse=True)
def _prod_environment_session():
    """Set ENVIRONMENT before class-scoped fixtures (e.g. catalog) run."""
    os.environ["ENVIRONMENT"] = "prod"
    ConfigurationService._instance_cache.clear()
    yield


@pytest.fixture(autouse=True)
def _prod_environment():
    """Clear ConfigurationService cache between tests."""
    ConfigurationService._instance_cache.clear()
    yield
