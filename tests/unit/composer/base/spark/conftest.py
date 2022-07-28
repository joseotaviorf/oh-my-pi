import pytest

from bietlejuice.base.spark import SparkDataFrameService


@pytest.fixture()
def dataframe_service():
    return SparkDataFrameService()
