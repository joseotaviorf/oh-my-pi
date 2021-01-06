import pytest

from bietlejuice.jobs.composer.base.spark import SparkDataFrameService


@pytest.fixture()
def dataframe_service():
    return SparkDataFrameService()
