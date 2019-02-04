import pytest
from datetime import datetime

from bietlejuice.jobs.etl.crm.tasks import CRMTasks, CRMTasksUngroupedManual, CRMTasksFactory, CRMTasksOffboarding

S3_BUCKET = 's3_bucket'
MONGO_CLIENT_URI = 'mongo_client_uri'
EXECUTION_DATE = datetime.today()


@pytest.fixture(scope='session')
def tasks():
    return CRMTasks(
        s3_bucket=S3_BUCKET,
        mongo_client_uri=MONGO_CLIENT_URI,
        execution_date=EXECUTION_DATE
    )


@pytest.fixture(scope='session')
def ungrouped_manual():
    return CRMTasksUngroupedManual(
        s3_bucket=S3_BUCKET,
        mongo_client_uri=MONGO_CLIENT_URI,
        execution_date=EXECUTION_DATE
    )


@pytest.fixture(scope='session')
def offboarding():
    return CRMTasksOffboarding(
        s3_bucket=S3_BUCKET,
        execution_date=EXECUTION_DATE
    )


@pytest.fixture(scope='session')
def factory():
    return CRMTasksFactory()
