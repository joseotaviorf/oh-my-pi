import mock

from bietlejuice.jobs.etl.kill_queue import KillQueueReservation


class TestKillQueueReservation(object):

    @mock.patch.object(KillQueueReservation, '_extract_data_and_move_to_raw')
    def test_extract_data_and_move_to_raw(self, mock__extract_data_and_move_to_raw, killqueue_reservation):
        # arrange
        table_name = killqueue_reservation.table_name

        # act
        killqueue_reservation.extract_data_and_move_to_raw()

        # assert
        assert mock__extract_data_and_move_to_raw.call_count == 1
        assert mock__extract_data_and_move_to_raw.call_args[0][0] == table_name

    @mock.patch.object(KillQueueReservation, '_move_data_from_raw_to_clean')
    def test_move_data_from_raw_to_clean(self, mock__move_data_from_raw_to_clean, killqueue_reservation):
        # arrange
        table_name = killqueue_reservation.table_name

        # act
        killqueue_reservation.move_data_from_raw_to_clean()

        # assert
        assert mock__move_data_from_raw_to_clean.call_count == 1
        assert mock__move_data_from_raw_to_clean.call_args[0][0] == table_name
