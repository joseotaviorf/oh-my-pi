from datetime import datetime

import pytest
from bietlejuice.jobs.etl.autodialer import AutodialerETL, AutodialerEnum

S3_BUCKET = 's3_bucket'
MONGO_CLIENT_URI = 'mongo_client_uri'
EXECUTION_DATE = datetime.today()


@pytest.fixture(scope='session')
def autodialer_etl():
    return AutodialerETL(
        mongo_client_uri=MONGO_CLIENT_URI,
        bucket_name=S3_BUCKET,
        document_type_enum=AutodialerEnum.TASK_REFERENCES,
        execution_date=EXECUTION_DATE
    )
