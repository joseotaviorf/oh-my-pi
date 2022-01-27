from unittest.mock import Mock

import pytest

from bietlejuice.jobs.composer.pipeline import SyncMetastoreExternalTableStructurePipeline


@pytest.fixture()
def metastore_external_table_pipeline():
    return SyncMetastoreExternalTableStructurePipeline(
        metastore_host=Mock(),
        database_name=Mock(),
        table_name=Mock(),
        database_location=Mock(),
        table_schema=Mock(),
        partition_keys=Mock(),
        partition_values=Mock(),
        format_info=Mock(),
    )
