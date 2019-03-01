import mock
import pytest

from bietlejuice.jobs.etl.kill_queue import KillQueueFactory, KillQueueHouse, KillQueueRentFlow, KillQueueReservation, \
    KillQueueReservationAud, KillQueueTableEnum


class TestKillQueueFactory(object):

    @pytest.mark.parametrize('table, expected', [
        (KillQueueTableEnum.HOUSE, KillQueueHouse),
        (KillQueueTableEnum.RENT_FLOW, KillQueueRentFlow),
        (KillQueueTableEnum.RESERVATION, KillQueueReservation),
        (KillQueueTableEnum.RESERVATION_AUD, KillQueueReservationAud)
    ])
    def test_factory(self, table, expected):
        # arrange
        s3_bucket = mock.ANY

        # act
        result = KillQueueFactory.factory(table, s3_bucket)

        # assert
        assert isinstance(result, expected)

    def test_factory_with_invalid_table(self):
        # arrange
        table = mock.ANY
        s3_bucket = mock.ANY

        # act
        with pytest.raises(RuntimeError):
            KillQueueFactory.factory(table, s3_bucket)
