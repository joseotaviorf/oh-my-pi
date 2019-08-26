import pytest

from bietlejuice.jobs.composer.base.spark import DataFrameService


@pytest.fixture()
def dataframe_service():
    return DataFrameService()
