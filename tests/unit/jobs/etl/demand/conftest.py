import pytest
from bietlejuice.jobs.etl.demand import DemandETL, ActiveUserSessionsETL, ActiveUsersETL

S3_BUCKET = '5a-datalake'


@pytest.fixture(scope='session')
def demand_etl():
    return DemandETL(
        s3_bucket=S3_BUCKET
    )


@pytest.fixture(scope='session')
def active_user_sessions_etl():
    return ActiveUserSessionsETL(
        s3_bucket=S3_BUCKET
    )


@pytest.fixture(scope='session')
def active_users_etl():
    return ActiveUsersETL(
        s3_bucket=S3_BUCKET
    )
