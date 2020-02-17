import mock

from bietlejuice.jobs.etl.kill_queue import KillQueueHouse


class TestKillQueueHouse(object):

    @mock.patch.object(KillQueueHouse, '_move_data_from_raw_to_clean')
    def test_move_data_from_raw_to_clean(self, mock__move_data_from_raw_to_clean, killqueue_house):
        # arrange
        table_name = killqueue_house.table_name

        # act
        killqueue_house.move_data_from_raw_to_clean()

        # assert
        assert mock__move_data_from_raw_to_clean.call_count == 1
        assert mock__move_data_from_raw_to_clean.call_args[0][0] == table_name
