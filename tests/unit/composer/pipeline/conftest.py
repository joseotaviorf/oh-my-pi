from unittest.mock import Mock

import pytest

from bietlejuice.jobs.composer.metastore_pipeline import (
    SyncMetastoreExternalTableStructurePipeline,
)
from bietlejuice.jobs.composer.metastore_pipeline import (
    SyncMetastoreExternalTablePartitionsPipeline,
)


@pytest.fixture()
def sync_metastore_external_table_structure_pipeline():
    return SyncMetastoreExternalTableStructurePipeline(
        metastore_host=Mock(),
        database_name=Mock(),
        table_name=Mock(),
        database_location=Mock(),
        table_schema=Mock(),
        partition_keys=Mock(),
        format_info=Mock(),
    )


@pytest.fixture()
def sync_metastore_external_table_partitions_pipeline():
    return SyncMetastoreExternalTablePartitionsPipeline(
        metastore_host=Mock(),
        database_name=Mock(),
        table_name=Mock(),
        partition_keys=Mock(),
        partition_values=Mock(),
    )
