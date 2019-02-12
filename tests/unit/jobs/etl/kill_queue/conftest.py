import pytest

from bietlejuice.jobs.etl.kill_queue import KillQueue
from bietlejuice.jobs.etl.kill_queue import KillQueueFactory, KillQueueHouse, KillQueueRentFlow, KillQueueReservation, \
    KillQueueReservationAud

S3_BUCKET = 's3-bucket'


@pytest.fixture(scope='session')
def factory():
    return KillQueueFactory()


@pytest.fixture(scope='session')
def kill_queue():
    return KillQueue(S3_BUCKET)


@pytest.fixture(scope='session')
def killqueue_house():
    return KillQueueHouse(S3_BUCKET)


@pytest.fixture(scope='session')
def killqueue_rent_flow():
    return KillQueueRentFlow(S3_BUCKET)


@pytest.fixture(scope='session')
def killqueue_reservation():
    return KillQueueReservation(S3_BUCKET)


@pytest.fixture(scope='session')
def killqueue_reservation_aud():
    return KillQueueReservationAud(S3_BUCKET)
