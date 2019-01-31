from datetime import datetime

import pytest

from bietlejuice.jobs.etl.marketing.criteo_campaigns import CriteoCampaigns

S3_BUCKET = 's3_bucket'
EXECUTION_DATE = datetime.today()
AUTH = {"client_id": "client_id", "client_secret": "client_secret", "user": "user"}


@pytest.fixture(scope='session')
def criteo_campaigns():
    return CriteoCampaigns(
        s3_bucket=S3_BUCKET,
        execution_date=EXECUTION_DATE,
        auth=AUTH,
    )
