import os
import sys
from pathlib import Path
from unittest.mock import MagicMock

os.environ.setdefault("ENVIRONMENT", "prod")

# Put the repo root on sys.path before ANYTHING else in this test session runs.
# bietlejuice.base.paths.DAG_PACKAGES_ROOT is computed once, at first import, by
# trying `import dags` (see _find_dag_packages_root()); if that first import
# happens before the repo root is on sys.path, it silently caches None for the
# rest of the process, and BaseDAG.get_dag_doc() then fails for every DAG test
# that resolves a doc file. test/unit/dags/conftest.py already does this
# insertion, but conftest loading follows collection order (e.g. "airflow/"
# sorts before "dags/"), so by the time it runs, some earlier-collected test
# may have already imported bietlejuice.base.paths and frozen the cache. This
# top-level conftest is loaded before collection descends into any
# subdirectory, so doing it here removes the order dependency.
_REPO_ROOT = Path(__file__).resolve().parents[4]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

# Stub private Nexus packages not available in local dev environment.
# These are only needed at runtime inside Databricks/Composer, not in unit tests.
for _private_pkg in [
    "databricks_plugin",
    "databricks_plugin.hooks",
    "databricks_plugin.hooks.databricks_hook",
    "extra_link_plugin",
    "quintoandar_logger",
]:
    sys.modules.setdefault(_private_pkg, MagicMock())


def pytest_collection_modifyitems(items):
    """
    Run raw_api_ingestion_workflow and reprocessing_guard_task_creator tests last
    to avoid test order sensitivity.

    RawAPIIngestionWorkflow imports BaseWorkflow, TaskCreatorFactory, JiraOpsCallback,
    ReprocessingGuardTaskCreator, and DatasetService. When those modules are loaded
    early in the test session, their module-level state (caches, registered classes,
    and patched callables) leaks into later tests, causing failures that don't appear
    when running the file in isolation. Deferring these tests to the end keeps the
    rest of the suite clean.
    """
    raw_api_items = [
        i for i in items if "test_raw_api_ingestion_workflow" in str(i.path)
    ]
    reprocessing_guard_items = [
        i for i in items if "test_reprocessing_guard_task_creator" in str(i.path)
    ]
    items_to_run_last = raw_api_items + reprocessing_guard_items
    if items_to_run_last:
        for i in items_to_run_last:
            items.remove(i)
        items.extend(items_to_run_last)
