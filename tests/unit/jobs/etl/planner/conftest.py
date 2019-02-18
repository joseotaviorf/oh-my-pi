from datetime import datetime

import pytest

from bietlejuice.jobs.etl.planner import Planner, PlannerAgent, PlannerRegion

S3_BUCKET = 's3-bucket'
EXECUTION_DATE = datetime.today()


@pytest.fixture(scope='session')
def planner():
    return Planner(S3_BUCKET, EXECUTION_DATE)


@pytest.fixture(scope='session')
def planner_agent():
    return PlannerAgent(S3_BUCKET, EXECUTION_DATE)


@pytest.fixture(scope='session')
def planner_region():
    return PlannerRegion(S3_BUCKET, EXECUTION_DATE)
