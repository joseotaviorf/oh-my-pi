import pytest

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


@pytest.fixture(autouse=True)
def clear_dag_packages_path_caches():
    """Avoid cross-test pollution from get_dag_path @lru_cache and line-folder cache."""
    DAGPackagesPathService.clear_path_caches()
    yield
    DAGPackagesPathService.clear_path_caches()


@pytest.fixture
def dag_package_service():
    return DAGPackagesPathService()
