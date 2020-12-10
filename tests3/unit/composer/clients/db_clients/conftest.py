import pytest
from unittest.mock import Mock
from bietlejuice.jobs.composer.clients.db_clients import SparkClient


@pytest.fixture()
def mocked_get_data_from_external_source():
    mock = Mock()
    attrs = {
        "read": mock,
        "format.return_value": mock,
        "options.return_value": mock,
        "path.return_value": mock,
    }
    mock.configure_mock(**attrs)
    return mock


@pytest.fixture()
def mocked_spark_client():
    return SparkClient()
