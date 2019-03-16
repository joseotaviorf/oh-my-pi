from datetime import datetime

import mock
import pytest

from bietlejuice.jobs.etl.seu_barriga import SeuBarrigaReport, SeuBarrigaInvoiceFactory, SeuBarrigaFine, \
    SeuBarrigaInvoice

S3_BUCKET = 's3_bucket'
TYPE_ = 'type_'
EXECUTION_DATE = datetime(2019, 1, 1)
API_DICT = {
    "token": "token",
    "endpoint": "endpoint",
    "job-waiting-time": 60
}


@pytest.fixture(scope='session')
def seu_barriga_report():
    return SeuBarrigaReport(
        s3_bucket=S3_BUCKET,
        api_dict=API_DICT,
        execution_date=EXECUTION_DATE
    )


@pytest.fixture(scope='session')
def seu_barriga_invoice_factory():
    return SeuBarrigaInvoiceFactory()


@pytest.fixture(scope='session')
def seu_barriga_fine():
    return SeuBarrigaFine(
        s3_bucket=S3_BUCKET,
        api_dict=API_DICT,
        execution_date=EXECUTION_DATE
    )


@pytest.fixture(scope='session')
def seu_barriga_invoice():
    return SeuBarrigaInvoice(
        s3_bucket=S3_BUCKET,
        type_=mock.ANY,
        year=EXECUTION_DATE.year,
        month=EXECUTION_DATE.month,
        api_dict=API_DICT
    )
