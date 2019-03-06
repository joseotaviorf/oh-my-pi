import pytest

from bietlejuice.jobs.etl.growth import Growth, GrowthPrediction


@pytest.fixture(scope='session')
def growth():
    return Growth()


@pytest.fixture(scope='session')
def growth_prediction():
    return GrowthPrediction()
