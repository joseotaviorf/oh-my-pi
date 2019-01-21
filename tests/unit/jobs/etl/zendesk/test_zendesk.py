import mock
from collections import OrderedDict
from datetime import datetime
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.zendesk import ZendeskETL


class TestZendeskETL(object):

    @mock.patch.object(AthenaClient, 'add_partition')
    @mock.patch.object(AthenaClient, 'create_parquet_from_query')
    @mock.patch.object(ZendeskETL, '_is_clean_table_empty', return_value=True)
    def test__move_to_clean_with_clean_table_empty(self, mock_is_clean_table_empty,
                                                   mock_create_parquet_from_query,
                                                   mock_add_partition, zendesk):
        # arrange
        table_name = 'table'
        key = 'raw/zendesk/class/dt=1999-01-01'
        query = 'select field_one, field_two, field_three from {}'
        raw_columns = OrderedDict([
            ('field_one', str),
            ('field_two', str),
            ('field_three', str)
        ])

        # act
        zendesk._move_to_clean(
            table_name=table_name,
            key=key,
            query=query,
            r_cols=raw_columns
        )

        # assert
        assert mock_add_partition.call_count == 1
        assert mock_add_partition.call_args[1]['table_name'] == 'zendesk_{}'.format(table_name)
        assert mock_add_partition.call_args[1]['partition'] == "dt_extraction='{}'".format(
            datetime.today().strftime('%Y-%m-%d'))
        assert mock_create_parquet_from_query.call_count == 1
        assert mock_create_parquet_from_query.call_args[1]['query'] == query
        assert mock_create_parquet_from_query.call_args[1]['key'] == key
        assert mock_create_parquet_from_query.call_args[1]['raw_columns'] == raw_columns
        assert mock_is_clean_table_empty.call_count == 1

    @mock.patch.object(AthenaClient, 'add_partition')
    @mock.patch.object(AthenaClient, 'create_parquet_from_query')
    @mock.patch.object(ZendeskETL, '_is_clean_table_empty', return_value=False)
    def test__move_to_clean_with_clean_table_not_empty(self, mock_is_clean_table_empty, mock_create_parquet_from_query,
                                                       mock_add_partition, zendesk):
        # arrange
        table_name = 'table'
        key = 'raw/zendesk/class/dt=1999-01-01'
        query = 'select field_one, field_two, field_three from {}'
        final_query = query + " \n where dt='{}'".format(datetime.today().strftime('%Y-%m-%d'))
        raw_columns = OrderedDict([
            ('field_one', str),
            ('field_two', str),
            ('field_three', str)
        ])

        # act
        zendesk._move_to_clean(
            table_name=table_name,
            key=key,
            query=query,
            r_cols=raw_columns
        )

        # assert
        assert mock_add_partition.call_count == 2
        assert mock_add_partition.call_args_list[0][1]['partition'] == "dt='{}'".format(
            datetime.today().strftime('%Y-%m-%d'))
        assert mock_add_partition.call_args_list[1][1]['table_name'] == 'zendesk_{}'.format(table_name)
        assert mock_add_partition.call_args_list[1][1]['partition'] == "dt_extraction='{}'".format(
            datetime.today().strftime('%Y-%m-%d'))
        assert mock_create_parquet_from_query.call_count == 1
        assert mock_create_parquet_from_query.call_args[1]['query'] == final_query
        assert mock_create_parquet_from_query.call_args[1]['key'] == key
        assert mock_create_parquet_from_query.call_args[1]['raw_columns'] == raw_columns
        assert mock_is_clean_table_empty.call_count == 1

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(ZendeskETL, '_move_to_clean')
    def test_tickets_with_right_query_path(self, mock__move_to_clean, mock_get_query_from_file_name, zendesk):
        # arrange
        table_name = 'tickets'

        zendesk.tickets(table_name)

        assert mock_get_query_from_file_name.call_count == 1
        assert mock_get_query_from_file_name.call_args[0][0] == '{}/zendesk/tickets.sql'.format(
            DATALAKE_QUERIES_DIR)
        assert mock__move_to_clean.call_count == 1
