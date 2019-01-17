import pytest
from airflow.models import DagBag


@pytest.fixture(scope='session')
def dag_bag():
    return DagBag()
