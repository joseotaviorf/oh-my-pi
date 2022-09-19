import pytest

from bietlejuice.base.airflow.dag_packages.dag_packages_path_service import (
    DAGPackagesPathService,
)


@pytest.fixture
def dag_package_service():
    return DAGPackagesPathService()
