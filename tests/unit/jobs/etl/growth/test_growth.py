import mock

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl.growth import Growth


class TestGrowth(object):
    @mock.patch.object(BaseETL, 'get_query_from_file_name', return_value=mock.ANY)
    def test_get_measure_all_query(self, mock_get_query_from_file_name, growth):
        # act
        result = growth.get_measure_all_query()

        # assert
        assert mock_get_query_from_file_name.call_count == 1
        assert 'measure_all.sql' in mock_get_query_from_file_name.call_args[0][0]

    @mock.patch.object(BaseETL, 'get_query_from_file_name', return_value=mock.ANY)
    def test_get_measure_no_filters_query(self, mock_get_query_from_file_name, growth):
        # act
        result = growth.get_measure_no_filters_query()

        # assert
        assert mock_get_query_from_file_name.call_count == 1
        assert 'measure_no_filters.sql' in mock_get_query_from_file_name.call_args[0][0]

    @mock.patch.object(BaseETL, 'get_query_from_file_name', return_value=mock.ANY)
    def test_get_employee_all_query(self, mock_get_employee_all_query, growth):
        # act
        result = growth.get_employee_all_query()

        # assert
        assert mock_get_employee_all_query.call_count == 1
        assert 'team_all.sql' in mock_get_employee_all_query.call_args[0][0]

    @mock.patch.object(Growth, 'drop_table')
    @mock.patch.object(Growth, '_execute_file_query')
    def test_load_fact(self, mock__execute_file_query, mock_drop_table, growth):
        # arrange
        fact_name = 'fact_growth'

        # act
        growth.load_fact()

        # assert
        assert mock__execute_file_query.call_count == 1
        assert mock_drop_table.call_count == 1
        assert mock_drop_table.call_args[1].get('table_name') == fact_name
        assert fact_name in mock__execute_file_query.call_args[0][0]

    @mock.patch.object(BaseETL, 'execute_command')
    def test_execute_command(self, mock_execute_command, growth):
        # arrange
        query = mock.ANY
        expected_dw_enum = EnumDB.BI_DW

        # act
        growth.execute_command(query)

        # assert
        assert mock_execute_command.call_count == 1
        assert mock_execute_command.call_args[1].get('command') == query
        assert mock_execute_command.call_args[1].get('db_enum') == expected_dw_enum

    @mock.patch.object(BaseETL, 'execute_file_query')
    def test__execute_file_query(self, mock_execute_file_query, growth):
        # arrange
        file_name = mock.ANY
        expected_dw_enum = EnumDB.BI_DW

        # act
        growth._execute_file_query(file_name)

        # assert
        assert mock_execute_file_query.call_count == 1
        assert mock_execute_file_query.call_args[1].get('file_name') == file_name
        assert mock_execute_file_query.call_args[1].get('db_enum') == expected_dw_enum

    @mock.patch.object(BaseETL, 'execute_command')
    def test_drop_table(self, mock_execute_command, growth):
        # arrange
        schema = mock.ANY
        table_name = mock.ANY
        expected_dw_enum = EnumDB.BI_DW
        command = 'drop table if exists {}.{};'.format(schema, table_name)

        # act
        growth.drop_table(table_name=table_name, schema=schema)

        # assert
        assert mock_execute_command.call_count == 1
        assert mock_execute_command.call_args[1].get('command') == command
        assert mock_execute_command.call_args[1].get('db_enum') == expected_dw_enum
