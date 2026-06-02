"""Shared stubs for core model DAG tests (Airflow plugins, private packages)."""

import sys
from unittest.mock import MagicMock

for _private_pkg in (
    "databricks_plugin",
    "databricks_plugin.hooks",
    "databricks_plugin.hooks.databricks_hook",
    "extra_link_plugin",
):
    sys.modules.setdefault(_private_pkg, MagicMock())
