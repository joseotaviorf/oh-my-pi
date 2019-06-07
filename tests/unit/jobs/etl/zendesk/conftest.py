import pytest
from datetime import datetime

from bietlejuice.jobs.etl.zendesk import Zendesk

S3_BUCKET = 's3_bucket'
EXECUTION_DATE = datetime(2018, 1, 1)


@pytest.fixture(scope='session')
def zendesk():
    return Zendesk(
        s3_bucket=S3_BUCKET,
        execution_date=EXECUTION_DATE
    )
