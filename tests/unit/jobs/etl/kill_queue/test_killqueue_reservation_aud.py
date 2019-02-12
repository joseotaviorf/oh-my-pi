import mock

from bietlejuice.jobs.etl.kill_queue import KillQueueReservationAud


class TestKillQueueReservationAud(object):

    @mock.patch.object(KillQueueReservationAud, '_extract_data_and_move_to_raw')
    def test_extract_data_and_move_to_raw(self, mock__extract_data_and_move_to_raw, killqueue_reservation_aud):
        # arrange
        table_name = killqueue_reservation_aud.table_name

        # act
        killqueue_reservation_aud.extract_data_and_move_to_raw()

        # assert
        assert mock__extract_data_and_move_to_raw.call_count == 1
        assert mock__extract_data_and_move_to_raw.call_args[0][0] == table_name

    @mock.patch.object(KillQueueReservationAud, '_move_data_from_raw_to_clean')
    def test_move_data_from_raw_to_clean(self, mock__move_data_from_raw_to_clean, killqueue_reservation_aud):
        # arrange
        table_name = killqueue_reservation_aud.table_name

        # act
        killqueue_reservation_aud.move_data_from_raw_to_clean()

        # assert
        assert mock__move_data_from_raw_to_clean.call_count == 1
        assert mock__move_data_from_raw_to_clean.call_args[0][0] == table_name
