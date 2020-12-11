from unittest.mock import Mock

import pytest

from bietlejuice.jobs.composer.services.metastore_services.hive_metastore_service import (
    HiveMetastoreService,
)


@pytest.fixture()
def hive_metastore_service():
    mocked_open_conn = Mock()
    mocked_open_conn.return_value = Mock()

    mocked_client = Mock()
    mocked_client.__enter__ = mocked_open_conn
    mocked_client.__exit__ = Mock()
    return HiveMetastoreService(client=mocked_client)
