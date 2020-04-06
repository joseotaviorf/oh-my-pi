import pytest
from unittest.mock import Mock
from bietlejuice.jobs.composer.loaders.spark_metastore_loader import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.clients.db_clients import SparkClient


@pytest.fixture()
def mocked_spark_df_writer():
    mock = Mock()
    return mock


@pytest.fixture()
def mocked_df():
    spark_client = SparkClient()
    return spark_client.create_dataframe([{"col1": "value", "col2": 123}])


@pytest.fixture()
def mocked_metastore_loader():
    return SparkMetastoreLoader


@pytest.fixture()
def mocked_s3_loader():
    return S3Loader(metastore_service='mock')
