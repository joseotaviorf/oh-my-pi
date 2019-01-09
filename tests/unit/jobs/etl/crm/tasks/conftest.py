from datetime import datetime

import pytest

from bietlejuice.jobs.etl.crm.tasks import CRMTasks

S3_BUCKET = 's3_bucket'


@pytest.fixture(scope='session')
def tasks():
    return CRMTasks(
        s3_bucket=S3_BUCKET,
        mongo_client_uri='mongo_client_uri',
        execution_date=datetime.today()
    )
