import pytest
from airflow.models import DagBag


@pytest.fixture(scope='session')
def get_dag_bag():
    return DagBag()
