import sys
from unittest.mock import MagicMock, patch
import pytest


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
