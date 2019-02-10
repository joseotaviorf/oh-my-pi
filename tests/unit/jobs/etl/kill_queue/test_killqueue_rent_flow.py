import mock

from bietlejuice.jobs.etl.kill_queue import KillQueueRentFlow


class TestKillQueueRentFlow(object):

    @mock.patch.object(KillQueueRentFlow, '_extract_data_and_move_to_raw')
    def test_extract_data_and_move_to_raw(self, mock__extract_data_and_move_to_raw, rent_flow):
        # arrange
        table_name = rent_flow.table_name

        # act
        rent_flow.extract_data_and_move_to_raw()

        # assert
        assert mock__extract_data_and_move_to_raw.call_count == 1
        assert mock__extract_data_and_move_to_raw.call_args[0][0] == table_name

    @mock.patch.object(KillQueueRentFlow, '_move_data_from_raw_to_clean')
    def test_move_data_from_raw_to_clean(self, mock__move_data_from_raw_to_clean, rent_flow):
        # arrange
        table_name = rent_flow.table_name

        # act
        rent_flow.move_data_from_raw_to_clean()

        # assert
        assert mock__move_data_from_raw_to_clean.call_count == 1
        assert mock__move_data_from_raw_to_clean.call_args[0][0] == table_name
