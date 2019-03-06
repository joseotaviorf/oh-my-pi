import mock
import pytest
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.base_etl import EnumDB
from bietlejuice.jobs.etl import SOURCE_QUERIES_DIR, DW_QUERIES_DIR, ODS_QUERIES_DIR


class TestAgents(object):
    @pytest.mark.parametrize('db_enum, dir', [(EnumDB.QuintoAndar_ebdb, '{}/ebdb'.format(SOURCE_QUERIES_DIR)),
                                              (EnumDB.BI_ODS, ODS_QUERIES_DIR),
                                              (EnumDB.BI_DW, '{}/public'.format(DW_QUERIES_DIR)),
                                              ('', ''),
                                              ])
    def test__format_query_filename(self, db_enum, dir, agent):
        # arrange
        filename = mock.ANY
        expected = '{}/{}.sql'.format(dir, filename)

        # act
        result = agent._format_query_filename(filename=filename, db_enum=db_enum)

        # assert
        assert result == expected

    @mock.patch.object(BaseETL, 'execute_command')
    def test_truncate_table(self, mock_execute_command, agent):
        # arrange
        schema = mock.ANY
        table = mock.ANY
        enumdb = mock.ANY
        expected = 'TRUNCATE TABLE {}.{}'.format(schema, table)

        # act
        agent.truncate_table(schema=schema, table=table, enumdb=enumdb)

        # assert
        assert mock_execute_command.call_count == 1
        assert mock_execute_command.call_args[1].get('db_enum') == enumdb
        assert mock_execute_command.call_args[1].get('command') == expected

    @mock.patch.object(BaseETL, 'decode_table', return_value=mock.ANY)
    @mock.patch.object(BaseETL, 'bulk_insert')
    def test_move_data_to_destination_decode_false(self, mock_bulk_insert, mock_decode_table, agent):
        # arrange
        decode = False
        data = mock.ANY
        table_name = mock.ANY

        # act
        agent.move_data_to_destination(data=data, table_name=table_name, decode=decode)

        # assert
        assert mock_decode_table.call_count == 0
        assert mock_bulk_insert.call_count == 1
        assert mock_bulk_insert.call_args[1].get('table') == data
        assert mock_bulk_insert.call_args[1].get('table_name') == table_name

    @mock.patch.object(BaseETL, 'decode_table', return_value=mock.ANY)
    @mock.patch.object(BaseETL, 'bulk_insert')
    def test_move_data_to_destination_decode_true(self, mock_bulk_insert, mock_decode_table, agent):
        # arrange
        decode = True
        data = mock.ANY
        table_name = mock.ANY

        # act
        agent.move_data_to_destination(data=data, table_name=table_name, decode=decode)

        # assert
        assert mock_decode_table.call_count == 1
        assert mock_bulk_insert.call_count == 1
        assert mock_bulk_insert.call_args[1].get('table') == mock_decode_table.return_value
        assert mock_bulk_insert.call_args[1].get('table_name') == table_name

    @pytest.mark.parametrize('decode, call_count', [(True, 1), (False, 0)])
    @mock.patch.object(BaseETL, 'decode_table', return_value=mock.ANY)
    @mock.patch.object(BaseETL, 'bulk_insert')
    def test_move_data_to_destination(self, mock_bulk_insert, mock_decode_table, decode, call_count, agent):
        # arrange
        data = mock.ANY
        table_name = mock.ANY
        expected_table = mock_decode_table.return_value if decode else data

        # act
        agent.move_data_to_destination(data=data, table_name=table_name, decode=decode)

        # assert
        assert mock_decode_table.call_count == call_count
        assert mock_bulk_insert.call_count == 1
        assert mock_bulk_insert.call_args[1].get('table') == expected_table
        assert mock_bulk_insert.call_args[1].get('table_name') == table_name

    def test__to_snake_case_columns(self, agent):
        # arrange
        old_columns = ['LoremIpsum']
        expected = {'LoremIpsum': 'lorem_ipsum'}

        # act
        result = agent._to_snake_case_columns(old_columns=old_columns)

        # assert
        assert result == expected

    @mock.patch.object(BaseETL, 'from_db_query', return_value=['', [1]])
    def test_check_dummy_exists_with_dummy(self, mock_from_db_query, agent):
        # arrange
        enumdb = mock.ANY
        schema = mock.ANY
        table_name = mock.ANY
        key_column = mock.ANY
        expected = True

        # act
        result = agent.check_dummy_exists(enumdb=enumdb, schema=schema, table_name=table_name, key_column=key_column)

        # assert
        assert mock_from_db_query.call_count == 1
        assert result == expected

    @mock.patch.object(BaseETL, 'from_db_query', return_value=['', [0]])
    def test_check_dummy_exists_without_dummy(self, mock_from_db_query, agent):
        # arrange
        enumdb = mock.ANY
        schema = mock.ANY
        table_name = mock.ANY
        key_column = mock.ANY
        query = 'SELECT count(1) FROM {}.{} WHERE {} = -1;'.format(schema, table_name, key_column)
        expected = False

        # act
        result = agent.check_dummy_exists(enumdb=enumdb, schema=schema, table_name=table_name, key_column=key_column)

        # assert
        assert mock_from_db_query.call_count == 1
        assert mock_from_db_query.call_args[1].get('query') == query
        assert result == expected
