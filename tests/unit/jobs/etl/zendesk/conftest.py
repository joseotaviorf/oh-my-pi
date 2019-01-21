import pytest
from datetime import datetime

from bietlejuice.jobs.etl.zendesk import ZendeskETL

S3_BUCKET = 's3_bucket'
EXECUTION_DATE = datetime.today()


@pytest.fixture(scope='session')
def zendesk():
    return ZendeskETL(
        bucket=S3_BUCKET,
        execution_date=EXECUTION_DATE
    )
