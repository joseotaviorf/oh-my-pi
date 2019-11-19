import pytest

from bietlejuice.jobs.etl.affiliate import AffiliateETL

S3_BUCKET = 's3_bucket'


@pytest.fixture(scope='session')
def affiliate_etl():
    return AffiliateETL()
