import mock
import pandas as pd

from qa_python_utils.aws.athena import AthenaClient
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.zendesk import Zendesk, ZendeskTableEnum
from collections import OrderedDict


class TestZendesk(object):

    @mock.patch.object(AthenaClient, 'create_parquet_from_query')
    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    def test_move_to_clean(self, mock_get_query_from_file_name, mock_create_parquet_from_query, zendesk):

        # arrange
        class_ = ZendeskTableEnum.TICKET_FIELDS
        # This moment, there are only partitioned tables.
        key = 'clean/zendesk/{0}/dt_extracted={1}/{1}.parq'.format(class_.value, zendesk.execution_date)
        r_cols = OrderedDict([
            ('col1', str),
            ('col2', str)
        ])
        c_cols = r_cols
        query = '{}/zendesk/{}.sql'.format(DATALAKE_QUERIES_DIR, class_.value)

        # act
        zendesk._move_to_clean(class_, key, r_cols, c_cols)

        # asserts
        assert mock_get_query_from_file_name.call_count == 1
        assert mock_create_parquet_from_query.call_count == 1
        assert mock_get_query_from_file_name.call_args[0][0] == query

    @mock.patch.object(Zendesk, '_move_to_clean')
    def test_move_to_clean_partitioned(self, mock_move_to_clean, zendesk):

        # arrange
        class_ = ZendeskTableEnum.TICKETS
        key = 'clean/zendesk/{0}/dt_extracted={1}/{1}.parq'.format(class_.value, zendesk.execution_date)
        r_cols = OrderedDict([
            ('col1', str),
            ('col2', str)
        ])
        c_cols = r_cols

        # act
        zendesk._move_to_clean_partitioned(class_, r_cols, c_cols)

        # asserts
        assert mock_move_to_clean.call_count == 1
        assert mock_move_to_clean.call_args[1]['class_'] in ZendeskTableEnum
        assert mock_move_to_clean.call_args[1]['key'] == key

    @mock.patch.object(AthenaClient, 'upsert_single_partition')
    def test_upsert_single_partition(self, mock_upsert_single_partition, zendesk):

        # arrange
        class_ = ZendeskTableEnum.TICKET_FIELDS
        bucket_type = 'clean'
        database = 'datalake_{}'.format(bucket_type)
        table = 'zendesk_{}'.format(class_.value)

        # act
        zendesk._upsert_single_partition(class_, bucket_type)

        # asserts
        assert mock_upsert_single_partition.call_count == 1
        assert mock_upsert_single_partition.call_args[1]['partition_name'] is not None
        assert mock_upsert_single_partition.call_args[1]['partition_value'] is not None
        assert mock_upsert_single_partition.call_args[1]['table'] == table
        assert mock_upsert_single_partition.call_args[1]['database'] == database

    @mock.patch.object(Zendesk, '_Zendesk__delete_old_entries')
    @mock.patch.object(BaseETL, 'bulk_insert')
    @mock.patch.object(AthenaClient, 'execute_query_and_return_dataframe', return_value=pd.DataFrame(['', '']))
    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(BaseETL, 'get_connection')
    def test_move_to_staging(self, mock_get_connection, mock_get_query_from_file_name, mock_execute_query_and_return_dataframe,
                             mock_bulk_insert, mock__Zendesk__delete_old_entries, zendesk):

        # arrange
        class_ = ZendeskTableEnum.FACT_TICKETS
        sk_field = 'sk_ticket'

        # act
        zendesk._move_to_staging(class_, sk_field)

        # asserts (# calls)
        assert mock_get_connection.call_count == 1
        assert mock_get_query_from_file_name.call_count == 2
        assert mock_bulk_insert.call_count == 1
        assert mock_execute_query_and_return_dataframe.call_count == 1
        assert mock__Zendesk__delete_old_entries.call_count == 1

        # asserts (returns and params)
        assert mock_bulk_insert.call_args[1]['table'] is not None
        assert mock_bulk_insert.call_args[1]['commit'] is False
        assert mock_bulk_insert.call_args[1]['append'] is False
        assert mock_bulk_insert.call_args[1]['conn'] == mock_get_connection.return_value
        assert mock_bulk_insert.call_args[1]['table_name'] == 'staging.zendesk_{}'.format(class_.value)

    @mock.patch.object(Zendesk, '_Zendesk__delete_old_entries')
    @mock.patch.object(BaseETL, 'bulk_insert')
    @mock.patch.object(BaseETL, 'from_db_query')
    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(BaseETL, 'get_connection')
    def test_move_to_prod(self, mock_get_connection, mock_get_query_from_file_name, mock_from_db_query,
                          mock_bulk_insert, mock__Zendesk__delete_old_entries, zendesk):
        # arrange
        class_ = ZendeskTableEnum.DIM_ZENDESK_USER
        sk_field = 'sk_zendesk_user'
        query = 'select distinct * from staging.zendesk_{};'.format(class_.value)

        # act
        zendesk._move_to_prod(class_, sk_field)

        # asserts
        assert mock_get_connection.call_count == 1
        assert mock_get_query_from_file_name.call_count == 1
        assert mock_from_db_query.call_count == 1
        assert mock__Zendesk__delete_old_entries.call_count == 1

        # asserts (returns and params)
        assert mock_bulk_insert.call_args[1]['table'] is not None
        assert mock_bulk_insert.call_args[1]['commit'] is True
        assert mock_bulk_insert.call_args[1]['append'] is True
        assert mock_bulk_insert.call_args[1]['conn'] == mock_get_connection.return_value
        assert mock_bulk_insert.call_args[1]['table_name'] == 'zendesk.{}'.format(class_.value)
        assert mock_from_db_query.call_args[1]['query'] == query
