import pytest
from airflow.models import DagBag

from bietlejuice.jobs.etl.marketing.marketing_enum import MarketingEnum

@pytest.fixture(scope='session')
def dag_bag():
    return DagBag()
