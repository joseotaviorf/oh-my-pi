import mock

from bietlejuice.jobs.etl.kill_queue import KillQueueRentFlow


class TestKillQueueRentFlow(object):

    @mock.patch.object(KillQueueRentFlow, '_move_data_from_raw_to_clean')
    def test_move_data_from_raw_to_clean(self, mock__move_data_from_raw_to_clean, killqueue_rent_flow):
        # arrange
        table_name = killqueue_rent_flow.table_name

        # act
        killqueue_rent_flow.move_data_from_raw_to_clean()

        # assert
        assert mock__move_data_from_raw_to_clean.call_count == 1
        assert mock__move_data_from_raw_to_clean.call_args[0][0] == table_name
