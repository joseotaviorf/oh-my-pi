import pytest
from datetime import datetime

from bietlejuice.jobs.etl.marketing import FacebookAds
from bietlejuice.jobs.etl.marketing import GoogleAds
from bietlejuice.jobs.etl.marketing import Marketing
from bietlejuice.jobs.etl.marketing.factory import MarketingFactory

S3_BUCKET = 's3_bucket'
EXECUTION_DATE = datetime(2018, 1, 1)
ACCOUNT = 'account'
INTEGRATION = 'integration'


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
