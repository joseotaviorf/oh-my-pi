import pytest
from datetime import datetime

from bietlejuice.jobs.etl.marketing.marketing import Marketing

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
def mkt_acc_integration():
    return Marketing(
        s3_bucket=S3_BUCKET,
        execution_date=EXECUTION_DATE,
        account=ACCOUNT,
        integration=INTEGRATION
    )
