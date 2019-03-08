import mock

from bietlejuice.jobs.etl.asterisk import AsteriskDevices, AsteriskTableEnum


class TestAsteriskDevices(object):

    @mock.patch.object(AsteriskDevices, '_extract_and_load_data_full')
    def test_extract_and_load_data(self, mock_extract_load_data, asterisk_devices):
        # arrange
        class_ = AsteriskTableEnum.DEVICES

        # act
        asterisk_devices.extract_and_load_data()

        # assert
        mock_extract_load_data.assert_called_once_with(class_=class_)

    @mock.patch.object(AsteriskDevices, '_data_existence_check_full')
    def test_data_existence_check(self, mock_data_existence, asterisk_devices):
        # arrange
        class_ = AsteriskTableEnum.DEVICES
        bucket_type = mock.ANY

        # act
        asterisk_devices.data_existence_check(bucket_type)

        # assert
        mock_data_existence.assert_called_once_with(bucket_type=bucket_type, class_=class_)

    @mock.patch.object(AsteriskDevices, '_move_to_clean_full')
    def test_move_to_clean(self, mock_move_to_clean, asterisk_devices):
        # arrange
        class_ = AsteriskTableEnum.DEVICES

        # act
        asterisk_devices.move_to_clean()

        # assert
        assert mock_move_to_clean.call_count == 1
        assert mock_move_to_clean.call_args[1]['class_'] == class_
        assert mock_move_to_clean.call_args[1]['r_cols'] is not None
        assert mock_move_to_clean.call_args[1]['c_cols'] is not None
