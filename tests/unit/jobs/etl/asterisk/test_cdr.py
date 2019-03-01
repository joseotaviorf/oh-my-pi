import mock

from bietlejuice.jobs.etl.asterisk import AsteriskCDR, AsteriskTableEnum


class TestAsteriskCDR(object):
    @mock.patch.object(AsteriskCDR, '_extract_and_load_data_partitioned')
    def test_extract_and_load_data(self, mock_extract_load_data, asterisk_cdr):
        # arrange
        class_ = AsteriskTableEnum.CDR

        # act
        asterisk_cdr.extract_and_load_data()

        # assert
        mock_extract_load_data.assert_called_once_with(class_=class_)

    @mock.patch.object(AsteriskCDR, '_data_existence_check_partitioned')
    def test_data_existence_check(self, mock_data_existence, asterisk_cdr):
        # arrange
        class_ = AsteriskTableEnum.CDR
        bucket_type = 'raw'

        # act
        asterisk_cdr.data_existence_check(bucket_type)

        # assert
        mock_data_existence.assert_called_once_with(bucket_type=bucket_type, class_=class_)

    @mock.patch.object(AsteriskCDR, '_move_to_clean_partitioned')
    def test_move_to_clean(self, mock_move_to_clean, asterisk_cdr):
        # arrange
        class_ = AsteriskTableEnum.CDR

        # act
        asterisk_cdr.move_to_clean()

        # assert
        assert mock_move_to_clean.call_count == 1
        assert mock_move_to_clean.call_args[1]['class_'] == class_
        assert mock_move_to_clean.call_args[1]['r_cols'] is not None
        assert mock_move_to_clean.call_args[1]['c_cols'] is not None
