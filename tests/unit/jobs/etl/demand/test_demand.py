import mock
import pandas as pd
import pytest
from bietlejuice.jobs.etl.demand import DemandETL
from qa_python_utils.aws.athena import AthenaClient


class TestDemandETL(object):

    def test__format_query_filename(self, demand_etl):
        # arrange
        filename = mock.ANY
        expected_result = 'demand/{}.sql'.format(filename)

        # act
        result = demand_etl._format_query_filename(filename=filename)

        # assert
        assert expected_result in result

    def test__get_dt_param_error(self, demand_etl):
        # arrange
        period = ''

        # act & assert
        with pytest.raises(ValueError):
            result = demand_etl._get_dt_param(period=period)

    @pytest.mark.parametrize('period, expected', [('daily', 'date'),
                                                  ('weekly', 'week_start'),
                                                  ('monthly', 'month_start')])
    def test__get_dt_param(self, period, expected, demand_etl):
        # act
        result = demand_etl._get_dt_param(period=period)

        # assert
        assert result == expected

    @mock.patch.object(DemandETL, '_get_dt_param', return_value='date')
    @mock.patch.object(DemandETL, '_format_query_filename', return_value='daily')
    @mock.patch.object(AthenaClient, 'execute_file_query_and_return_dataframe',
                       return_value=pd.DataFrame(data=[1], columns=['id']))
    def test__extract_data(self, mock_execute_file_query_and_return_dataframe, mock__format_query_filename,
                           mock__get_dt_param, demand_etl):
        # arrange
        table_name = mock.ANY
        period = mock.ANY
        expected_result = pd.DataFrame(data=[1], columns=['id'])
        expected_dict = {'dt_column': 'date'}

        # act
        result = demand_etl._extract_data(table_name=table_name, period=period)

        # assert
        assert mock_execute_file_query_and_return_dataframe.call_count == 1
        assert mock__format_query_filename.call_count == 1
        assert mock__get_dt_param.call_count == 1
        assert mock__get_dt_param.call_args[1].get('period') == period
        assert mock__format_query_filename.call_args[1].get('filename') == mock.ANY
        assert mock_execute_file_query_and_return_dataframe.call_args[1].get('filename') == 'daily'
        assert mock_execute_file_query_and_return_dataframe.call_args[1].get('query_params') == expected_dict
        assert result.equals(expected_result)

    @mock.patch.object(AthenaClient, 'create_parquet_from_df')
    def test__move_to_datalake(self, mock_create_parquet_from_df, demand_etl):
        # arrange
        df = mock.ANY
        table_name = mock.ANY
        period = mock.ANY
        raw_columns = mock.ANY
        clean_columns = mock.ANY
        expected_s3_file_path = '{0}/{0}'.format('{}_{}'.format(period, table_name))

        # act
        demand_etl._move_to_datalake(df=df, table_name=table_name, period=period, raw_columns=raw_columns,
                                     clean_columns=clean_columns)

        # assert
        assert mock_create_parquet_from_df.call_count == 1
        assert expected_s3_file_path in mock_create_parquet_from_df.call_args[1].get('key')
        assert mock_create_parquet_from_df.call_args[1].get('df') == df
        assert mock_create_parquet_from_df.call_args[1].get('raw_columns') == raw_columns
        assert mock_create_parquet_from_df.call_args[1].get('clean_columns') == clean_columns
