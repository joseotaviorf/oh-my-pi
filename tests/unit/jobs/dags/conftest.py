import pytest
from airflow.models import DagBag

from bietlejuice.jobs.dags.marketing.marketing_twitter_campaigns_subdag import \
    MarketingTwitterCampaignsSubDag
from bietlejuice.jobs.etl.marketing.marketing_enum import MarketingEnum


@pytest.fixture(scope='session')
def dag_bag():
    return DagBag()


@pytest.fixture
def twitter_campaigns_subdag():
    return MarketingTwitterCampaignsSubDag(MarketingEnum.TWITTER, 'bucket',
                                           'sub_dag_name', 'dag_name',
                                           'schedule_interval', 'start_date', 'auth',
                                           end_date=None, accounts=None,
                                           extra_configs=None)
