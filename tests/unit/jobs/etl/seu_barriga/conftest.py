from datetime import datetime

import mock
import pytest
from bietlejuice.jobs.etl.seu_barriga import SeuBarrigaReport, SeuBarrigaInvoiceFactory, SeuBarrigaFine, \
    SeuBarrigaInvoice

S3_BUCKET = '5a-datalake'
API_DICT = """
    {
    "invoice": {"token": "LoremIpsum",
        "endpoint": "http://seubarriga.quintoandar.com.br/",
        "job-waiting-time": 60
        }
    }
    """
EXECUTION_DATE = datetime.now()


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
        _type=mock.ANY,
        year=2019,
        month=01,
        api_dict=API_DICT
    )
