import pandas as pd
import pytest

from bietlejuice.jobs.base.data_frame_service import DataFrameJsonService, DataFrameCSVService, DataFrameService

DF = pd.DataFrame({
    'col0': [1, 'row1'],
    'col1': ['row0', 2]
})


@pytest.fixture(scope='session')
def data_frame_service():
    return DataFrameService(df=DF)


@pytest.fixture(scope='session')
def data_frame_csv_service():
    return DataFrameCSVService(df=DF)


@pytest.fixture(scope='session')
def data_frame_json_service():
    return DataFrameJsonService(df=DF)
