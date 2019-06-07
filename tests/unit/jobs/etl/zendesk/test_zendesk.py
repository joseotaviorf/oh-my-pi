import mock
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
        assert query == mock_get_query_from_file_name.call_args[0][0]

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

    # @mock.patch.object(Zendesk, '_upsert_single_partition')
    # def test_upsert_single_partition(zendesk, class_, bucket_type):

    # @mock.patch.object(Zendesk, '_move_to_staging')
    # def test_move_to_staging(zendesk, class_, sk_field):

    # @mock.patch.object(Zendesk, '_move_to_prod')
    # def test_move_to_prod(zendesk, class_, sk_field):

    # @mock.patch.object(Zendesk, '__delete_old_entries')
    # def test__delete_old_entries(delete_query, commit, conn=False):
