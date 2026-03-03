import sys
from unittest.mock import MagicMock, patch
import pytest


def pytest_collection_modifyitems(items):
    """
    Run raw_api_ingestion_workflow tests last to avoid test order sensitivity.

    RawAPIIngestionWorkflow imports BaseWorkflow, TaskCreatorFactory, JiraOpsCallback,
    ReprocessingGuardTaskCreator, and DatasetService. When those modules are loaded
    before other tests run, patches in test_reprocessing_guard_task_creator,
    test_jiraops_callback, and test_dataset_service fail because the modules
    already hold references to the real implementations. Running the workflow
    tests last ensures the other tests run with clean module state.
    """
    raw_api_items = [
        i for i in items if "test_raw_api_ingestion_workflow" in str(i.path)
    ]
    if raw_api_items:
        for i in raw_api_items:
            items.remove(i)
        items.extend(raw_api_items)


# Mock external plugins that might not be installed locally
sys.modules["databricks_plugin"] = MagicMock()
sys.modules["extra_link_plugin"] = MagicMock()


@pytest.fixture(scope="session", autouse=True)
def setup_airflow_hooks():
    """
    Mock Airflow core hooks to prevent ProvidersManager initialization issues.
    The ProvidersManager tries to import FSHook and PackageIndexHook which can
    fail in CI environments with missing dependencies.
    """
    # Mock the problematic hooks before they're imported
    mock_fs_hook = MagicMock()
    mock_fs_hook.__name__ = "FSHook"
    mock_fs_hook.__module__ = "airflow.hooks.filesystem"

    mock_package_hook = MagicMock()
    mock_package_hook.__name__ = "PackageIndexHook"
    mock_package_hook.__module__ = "airflow.hooks.package_index"

    # Mock the hook imports to prevent the adapter error
    with patch.dict(
        "sys.modules",
        {
            "airflow.hooks.filesystem": MagicMock(FSHook=mock_fs_hook),
            "airflow.hooks.package_index": MagicMock(
                PackageIndexHook=mock_package_hook
            ),
        },
    ):
        yield
