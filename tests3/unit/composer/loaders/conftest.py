import pytest
from unittest.mock import Mock
from bietlejuice.jobs.composer.loaders.spark_metastore_loader import (
    SparkMetastoreLoader,
)
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader


@pytest.fixture()
def mocked_write_df():
    mock = Mock()
    mock.dataframe = mock
    mock.write = mock
    return mock


@pytest.fixture()
def metastore_loader():
    mock = Mock()
    attrs = {"get_table_names.return_value": []}
    mock.configure_mock(**attrs)
    return SparkMetastoreLoader(mock)


@pytest.fixture()
def s3_loader():
    return S3Loader()
