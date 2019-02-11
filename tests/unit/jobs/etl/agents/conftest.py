import pytest

from bietlejuice.jobs.etl.agents import Agent, Bridge

S3_BUCKET = 's3_bucket'


@pytest.fixture(scope='session')
def agents():
    return Agent(
        bucket_name=S3_BUCKET
    )


@pytest.fixture(scope='session')
def bridge():
    return Bridge(
        bucket_name=S3_BUCKET
    )
