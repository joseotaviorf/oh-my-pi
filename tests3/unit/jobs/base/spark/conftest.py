import pytest

from bietlejuice.jobs.composer.services import SparkDataFrameService


@pytest.fixture()
def dataframe_service():
    return SparkDataFrameService()
