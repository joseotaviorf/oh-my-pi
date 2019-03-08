import mock

from bietlejuice.jobs.etl.asterisk import AsteriskQueuesDetails, AsteriskTableEnum


class TestAsteriskQueuesDetails(object):

    @mock.patch.object(AsteriskQueuesDetails, '_extract_and_load_data_full')
    def test_extract_and_load_data(self, mock_extract_load_data, asterisk_queues_details):
        # arrange
        class_ = AsteriskTableEnum.QUEUES_DETAILS

        # act
        asterisk_queues_details.extract_and_load_data()

        # assert
        mock_extract_load_data.assert_called_once_with(class_=class_)

    @mock.patch.object(AsteriskQueuesDetails, '_data_existence_check_full')
    def test_data_existence_check(self, mock_data_existence, asterisk_queues_details):
        # arrange
        class_ = AsteriskTableEnum.QUEUES_DETAILS
        bucket_type = mock.ANY

        # act
        asterisk_queues_details.data_existence_check(bucket_type)

        # assert
        mock_data_existence.assert_called_once_with(bucket_type=bucket_type, class_=class_)

    @mock.patch.object(AsteriskQueuesDetails, '_move_to_clean_full')
    def test_move_to_clean(self, mock_move_to_clean, asterisk_queues_details):
        # arrange
        class_ = AsteriskTableEnum.QUEUES_DETAILS

        # act
        asterisk_queues_details.move_to_clean()

        # assert
        assert mock_move_to_clean.call_count == 1
        assert mock_move_to_clean.call_args[1]['class_'] == class_
        assert mock_move_to_clean.call_args[1]['r_cols'] is not None
        assert mock_move_to_clean.call_args[1]['c_cols'] is not None
