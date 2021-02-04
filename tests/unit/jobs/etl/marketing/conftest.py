from datetime import datetime

import pytest

from bietlejuice.jobs.etl.marketing import RtbCampaigns
from bietlejuice.jobs.etl.marketing import FacebookAds
from bietlejuice.jobs.etl.marketing import GoogleAds
from bietlejuice.jobs.etl.marketing import LifullCampaigns
from bietlejuice.jobs.etl.marketing import Marketing
from bietlejuice.jobs.etl.marketing import TwitterCampaigns
from bietlejuice.jobs.etl.marketing.factory import MarketingFactory

S3_BUCKET = 's3_bucket'
EXECUTION_DATE = datetime(2018, 1, 1)
ACCOUNT = 'account'
INTEGRATION = 'integration'
AUTH = {"client_id": "client_id", "client_secret": "client_secret", "user": "user"}


@pytest.fixture(scope='session')
def marketing():
    return Marketing(
        s3_bucket=S3_BUCKET,
        execution_date=EXECUTION_DATE
    )


@pytest.fixture(scope='session')
def google_ads():
    return GoogleAds(
        S3_BUCKET,
        EXECUTION_DATE,
        None
    )


@pytest.fixture(scope='session')
def facebook_ads():
    return FacebookAds(
        S3_BUCKET,
        EXECUTION_DATE,
        None
    )


@pytest.fixture(scope='session')
def mkt_acc_integration():
    return Marketing(
        s3_bucket=S3_BUCKET,
        execution_date=EXECUTION_DATE,
        account=ACCOUNT,
        integration=INTEGRATION
    )


@pytest.fixture(scope='session')
def factory():
    return MarketingFactory()


@pytest.fixture
def twitter_campaigns():
    return TwitterCampaigns(
        s3_bucket=S3_BUCKET,
        execution_date=EXECUTION_DATE,
        auth={"consumer_key": "consumer_key",
              "consumer_secret": "consumer_secret",
              "access_token": "access_token",
              "access_token_secret": "access_token_secret"}
    )


@pytest.fixture
def lifull_campaigns():
    return LifullCampaigns(
        s3_bucket=S3_BUCKET,
        execution_date=EXECUTION_DATE,
        auth=None,
        account=None
    )
