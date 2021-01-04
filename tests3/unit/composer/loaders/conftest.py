from unittest.mock import Mock

import pytest

from bietlejuice.jobs.composer.loaders import HiveMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.loaders.spark_metastore_loader import (
    SparkMetastoreLoader,
)


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


@pytest.fixture()
def hive_metastore_loader():
    return HiveMetastoreLoader(metastore_service=Mock())
