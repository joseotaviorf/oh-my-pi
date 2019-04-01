import mock
import pandas as pd
from bietlejuice.jobs.etl.demand import ActiveUserSessionsETL, DemandEnum


class TestActiveUserSessionsETL(object):

    @mock.patch.object(ActiveUserSessionsETL, '_move_to_datalake')
    def test_move_to_datalake(self, mock__move_to_datalake, active_user_sessions_etl):
        # arrange
        df = pd.DataFrame(data=[1], columns=['id'])
        period = mock.ANY
        expected_cols_length = 16
        expected_table_name = DemandEnum.ACTIVE_USER_SESSIONS.value

        # act
        active_user_sessions_etl.move_to_datalake(df=df, period=period)

        # assert
        assert mock__move_to_datalake.call_count == 1
        assert mock__move_to_datalake.call_args[1].get('df').equals(df)
        assert mock__move_to_datalake.call_args[1].get('table_name') == expected_table_name
        assert mock__move_to_datalake.call_args[1].get('period') == period
        assert len(mock__move_to_datalake.call_args[1].get('raw_columns')) == expected_cols_length
        assert len(mock__move_to_datalake.call_args[1].get('clean_columns')) == expected_cols_length
        for item in mock__move_to_datalake.call_args[1].get('raw_columns'):
            assert isinstance(item, str)
        for item in mock__move_to_datalake.call_args[1].get('clean_columns'):
            assert isinstance(item, str)

    @mock.patch.object(ActiveUserSessionsETL, '_extract_data')
    def test_extract_data(self, mock__extract_data, active_user_sessions_etl):
        # arrange
        period = mock.ANY
        expected_table_name = DemandEnum.ACTIVE_USER_SESSIONS.value

        # act
        active_user_sessions_etl.extract_data(period=period)

        # assert
        assert mock__extract_data.call_count == 1
        assert mock__extract_data.call_args[1].get('table_name') == expected_table_name
        assert mock__extract_data.call_args[1].get('period') == period
