import pytest

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


@pytest.fixture
def dag_package_service():
    return DAGPackagesPathService()
