import pytest
import mock

from mock import MagicMock

from bietlejuice.jobs.composer.base.db.database_client_factory import (
    DatabaseClientFactory,
)

from bietlejuice.jobs.composer.clients.db_clients import PostgresClient
from bietlejuice.jobs.composer.clients.db_clients import AthenaClient
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.clients.db_clients import MongoClient


class TestDatabaseClientFactory:
    @pytest.mark.parametrize(
        "client,expected_client",
        [
            (DatabaseClientFactory.get_client("postgres")(), PostgresClient),
            (DatabaseClientFactory.get_client("mongo")(MagicMock()), MongoClient),
            (DatabaseClientFactory.get_client("athena")(mock.ANY), AthenaClient),
            (DatabaseClientFactory.get_client("spark")(mock.ANY), SparkClient),
        ],
    )
    def test_client(self, client, expected_client):
        # assert
        assert isinstance(client, expected_client)
