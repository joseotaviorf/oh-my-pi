import pytest
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader


@pytest.fixture()
def mocked_df():
    spark_client = SparkClient()
    return spark_client.create_dataframe([{"col1": "value", "col2": 123}])


@pytest.fixture()
def mocked_s3_loader():
    return S3Loader(metastore_service='mock')
