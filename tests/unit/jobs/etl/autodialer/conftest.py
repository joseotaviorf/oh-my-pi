from datetime import datetime

import pytest
from bietlejuice.jobs.etl.autodialer import AutodialerETL, AutodialerEnum


@pytest.fixture(scope='session')
def autodialer_etl():
    return AutodialerETL(
        mongo_client_uri='mongo_client_uri',
        bucket_name='s3_bucket',
        document_type_enum=AutodialerEnum.TASK_REFERENCES,
        execution_date=datetime.today()
    )
