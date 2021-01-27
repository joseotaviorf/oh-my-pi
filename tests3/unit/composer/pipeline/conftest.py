from unittest.mock import Mock

import pytest

from bietlejuice.jobs.composer.pipeline import MetastoreExternalTablePipeline


@pytest.fixture()
def metastore_external_table_pipeline():
    return MetastoreExternalTablePipeline(
        metastore_host=Mock(),
        database_name=Mock(),
        table_name=Mock(),
        database_location=Mock(),
        table_schema=Mock(),
        partition_keys=Mock(),
        partition_values=Mock(),
        format_info=Mock(),
    )
