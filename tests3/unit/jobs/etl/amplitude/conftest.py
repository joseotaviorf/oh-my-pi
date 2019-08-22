import pytest

from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents

class MockedDataFrameService():
    @staticmethod
    def incremental_write(df, file_format, partition_by_list, db, table_name, path, schema_merging=False):
        return

@pytest.fixture()
def amplitude_events():
    return AmplitudeEvents()
