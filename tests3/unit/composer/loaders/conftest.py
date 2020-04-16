import pytest
from unittest.mock import Mock
from bietlejuice.jobs.composer.loaders.spark_metastore_loader import SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.clients.db_clients import SparkClient


@pytest.fixture()
def mocked_write_df():
    mock = Mock()
    mock.dataframe = mock
    mock.write = mock
    return mock


@pytest.fixture()
def metastore_loader():
    spark_client = SparkClient()
    metastore_service = SparkMetastoreService(spark_client)
    return SparkMetastoreLoader(metastore_service)


@pytest.fixture()
def s3_loader():
    return S3Loader()
