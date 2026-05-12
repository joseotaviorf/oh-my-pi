import pytest

from bietlejuice.base.spark.spark_dataframe_service import SparkDataFrameService


@pytest.fixture()
def dataframe_service():
    return SparkDataFrameService()
