from datetime import datetime

import pytest

from bietlejuice.jobs.etl.crm.tasks import CRMTasks, CRMTasksUngroupedManual, CRMTasksFactory, CRMTasksOffboarding, \
    CRMTasksClosing, CRMTasksRepair, CRMTasksInspection, CRMTasksLead, CRMTasksOnboardingTenant, CRMTasksPayment, \
    CRMTasksPhotoJob, CRMTasksVisit, CRMTasksCredit

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
def closing():
    return CRMTasksClosing(
        s3_bucket=S3_BUCKET,
        mongo_client_uri=MONGO_CLIENT_URI,
        execution_date=EXECUTION_DATE
    )


@pytest.fixture(scope='session')
def credit():
    return CRMTasksCredit(
        s3_bucket=S3_BUCKET,
        mongo_client_uri=MONGO_CLIENT_URI,
        execution_date=EXECUTION_DATE
    )


@pytest.fixture(scope='session')
def photo_job():
    return CRMTasksPhotoJob(
        s3_bucket=S3_BUCKET,
        mongo_client_uri=MONGO_CLIENT_URI,
        execution_date=EXECUTION_DATE
    )


@pytest.fixture(scope='session')
def repair():
    return CRMTasksRepair(
        s3_bucket=S3_BUCKET,
        mongo_client_uri=MONGO_CLIENT_URI,
        execution_date=EXECUTION_DATE
    )


@pytest.fixture(scope='session')
def visit():
    return CRMTasksVisit(
        s3_bucket=S3_BUCKET,
        mongo_client_uri=MONGO_CLIENT_URI,
        execution_date=EXECUTION_DATE
    )


@pytest.fixture(scope='session')
def payment():
    return CRMTasksPayment(
        s3_bucket=S3_BUCKET,
        mongo_client_uri=MONGO_CLIENT_URI,
        execution_date=EXECUTION_DATE
    )


@pytest.fixture(scope='session')
def onboarding_tenant():
    return CRMTasksOnboardingTenant(
        s3_bucket=S3_BUCKET,
        mongo_client_uri=MONGO_CLIENT_URI,
        execution_date=EXECUTION_DATE
    )


@pytest.fixture(scope='session')
def lead():
    return CRMTasksLead(
        s3_bucket=S3_BUCKET,
        mongo_client_uri=MONGO_CLIENT_URI,
        execution_date=EXECUTION_DATE
    )


@pytest.fixture(scope='session')
def inspection():
    return CRMTasksInspection(
        s3_bucket=S3_BUCKET,
        mongo_client_uri=MONGO_CLIENT_URI,
        execution_date=EXECUTION_DATE
    )


@pytest.fixture(scope='session')
def factory():
    return CRMTasksFactory()
