import mock
import pytest

from bietlejuice.jobs.etl.kenshoo import Kenshoo


@pytest.fixture(scope='session')
def kenshoo():
    return Kenshoo(
        athena_client=mock.ANY,
        execution_date=mock.ANY
    )
