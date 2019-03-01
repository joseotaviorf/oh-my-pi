import mock

from bietlejuice.jobs.etl.asterisk import AsteriskUsers, AsteriskTableEnum


class TestAsteriskUsers(object):

    @mock.patch.object(AsteriskUsers, '_extract_and_load_data_full')
    def test_extract_and_load_data(self, mock_extract_load_data, asterisk_users):
        # arrange
        class_ = AsteriskTableEnum.USERS

        # act
        asterisk_users.extract_and_load_data()

        # assert
        mock_extract_load_data.assert_called_once_with(class_=class_)

    @mock.patch.object(AsteriskUsers, '_data_existence_check_full')
    def test_data_existence_check(self, mock_data_existence, asterisk_users):
        # arrange
        class_ = AsteriskTableEnum.USERS
        bucket_type = 'raw'

        # act
        asterisk_users.data_existence_check(bucket_type)

        # assert
        mock_data_existence.assert_called_once_with(bucket_type=bucket_type, class_=class_)

    @mock.patch.object(AsteriskUsers, '_move_to_clean_full')
    def test_move_to_clean(self, mock_move_to_clean, asterisk_users):
        # arrange
        class_ = AsteriskTableEnum.USERS

        # act
        asterisk_users.move_to_clean()

        # assert
        assert mock_move_to_clean.call_count == 1
        assert mock_move_to_clean.call_args[1]['class_'] == class_
        assert mock_move_to_clean.call_args[1]['r_cols'] is not None
        assert mock_move_to_clean.call_args[1]['c_cols'] is not None
