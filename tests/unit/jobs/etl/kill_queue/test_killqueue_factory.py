import mock
import pytest

from bietlejuice.jobs.etl.kill_queue import KillQueueHouse, KillQueueRentFlow, KillQueueReservation, \
    KillQueueReservationAud, KillQueueTableEnum


class TestKillQueueFactory(object):

    @pytest.mark.parametrize('table, expected', [
        (KillQueueTableEnum.HOUSE, KillQueueHouse),
        (KillQueueTableEnum.RENT_FLOW, KillQueueRentFlow),
        (KillQueueTableEnum.RESERVATION, KillQueueReservation),
        (KillQueueTableEnum.RESERVATION_AUD, KillQueueReservationAud)
    ])
    def test_get_object(self, table, expected, factory):
        # arrange
        s3_bucket = mock.ANY

        # act
        result = factory.get_object(table, s3_bucket)

        # assert
        assert isinstance(result, expected)

    def test_get_object_with_table_none(self, factory):
        # arrange
        table = None
        s3_bucket = mock.ANY

        # act
        with pytest.raises(ValueError):
            factory.get_object(table, s3_bucket)

    def test_get_object_with_invalid_table_none(self, factory):
        # arrange
        table = mock.ANY
        s3_bucket = mock.ANY

        # act
        with pytest.raises(RuntimeError):
            factory.get_object(table, s3_bucket)
