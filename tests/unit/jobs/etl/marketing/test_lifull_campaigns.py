from collections import OrderedDict

import mock
import pytest
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.marketing.lifull_campaigns import LifullCampaigns
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.aws.batch import BatchClient


class TestLifullCampaigns(object):

    @mock.patch.object(BatchClient, 'start_batch_job')
    @mock.patch.object(BatchClient, 'get_job_info_by_id')
    def test_move_lifull_campaigns_to_raw_with_failed_batch_return(self, mock_get_job_info_by_id, mock_start_batch_job,
                                                                   lifull_campaigns):
        # arrange
        mock_get_job_info_by_id.return_value = {'status': 'FAILED'}

        # act & assert
        with pytest.raises(RuntimeError):
            lifull_campaigns.move_lifull_campaigns_to_raw()

    @mock.patch.object(BatchClient, 'start_batch_job')
    @mock.patch.object(BatchClient, 'get_job_info_by_id')
    def test_move_lifull_campaigns_to_raw_with_succeeded_batch_return(self, mock_get_job_info_by_id,
                                                                      mock_start_batch_job,
                                                                      lifull_campaigns):
        # arrange
        expected_result = {'jobId': 10}
        mock_start_batch_job.return_value = expected_result
        mock_get_job_info_by_id.return_value = {'status': 'SUCCEEDED'}

        # act
        lifull_campaigns.move_lifull_campaigns_to_raw()

        # assert
        mock_start_batch_job.assert_called_once()
        assert mock_get_job_info_by_id.call_count == 2
        mock_get_job_info_by_id.assert_called_with(expected_result.get('jobId'))

    @mock.patch.object(AthenaClient, 'add_partition')
    @mock.patch.object(AthenaClient, 'create_parquet_from_query')
    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    def test_move_to_clean(self, mock_get_query_from_file_name, mock_create_parquet_from_query, mock_add_partition,
                           lifull_campaigns):
        # arrange
        table_name = 'table'
        sql_file_name = 'sql'
        group_name = 'group_name'
        r_cols = OrderedDict([
            ('col1', str),
            ('col2', str)
        ])
        schema = 'datalake_clean'
        expect_key = 'clean/marketing/lifull_campaigns/table/acc=None/group_name=group_name/' \
                     'dt_created=2018-01-01/2018-01-01.parquet'
        expect_query_path = '/marketing/lifull_campaigns/raw_to_clean/sql'
        expect_partition = "dt_created='2018-01-01', acc='None', group_name='group_name'"

        # act
        lifull_campaigns._move_to_clean(table_name, sql_file_name, group_name, r_cols)

        # assert
        assert expect_query_path in mock_get_query_from_file_name.call_args[0][0]
        mock_get_query_from_file_name.assert_called_once()
        mock_add_partition.assert_called_with(database=schema, table_name=table_name, partition=expect_partition)
        assert mock_add_partition.call_count == 2
        assert mock_create_parquet_from_query.call_args[1]['key'] == expect_key
        mock_create_parquet_from_query.assert_called_once()

    @mock.patch.object(LifullCampaigns, '_move_to_clean')
    def test_move_marketing_lifull_campaigns_to_clean(self, mock__move_to_clean, lifull_campaigns):
        # arrange
        expected_table_name = 'marketing_lifull_campaigns'
        expected_sql_file_name = 'lifull_campaigns.sql'
        r_cols = OrderedDict([
            ('id', str),
            ('name', str),
            ('clicks', str),
            ('desktop_cost', str),
            ('mobile_cost', str),
            ('total_cost', str),
            ('curr_date', str)
        ])
        group_name = mock.ANY

        # act
        lifull_campaigns.move_marketing_lifull_campaigns_to_clean(group_name=mock.ANY)

        # assert
        mock__move_to_clean.assert_called_once_with(table_name=expected_table_name,
                                                    sql_file_name=expected_sql_file_name,
                                                    group_name=lifull_campaigns.group_names,
                                                    r_cols=r_cols,
                                                    c_cols=r_cols)

    @mock.patch.object(LifullCampaigns, '_load_table')
    @mock.patch.object(LifullCampaigns, '_load_to_staging')
    def test_load_to_staging(self, mock__load_to_staging, mock__load_table,
                             lifull_campaigns):
        # arrange
        dw_table_name = mock.ANY
        query = '{date} {account}'
        formatted_query = '2018-01-01 default'
        mock__load_table.return_value = query

        # act
        lifull_campaigns.load_to_staging(dw_table_name)

        # assert
        mock__load_to_staging.assert_called_once_with(dw_table_name, formatted_query)

    @mock.patch.object(LifullCampaigns, '_load_dim_to_staging')
    def test__load_table_dim(self, mock__load_dim_to_staging, lifull_campaigns):
        # arrange
        table_name = 'dim_foo_bar'

        # act
        lifull_campaigns._load_table(table_name)

        # assert
        mock__load_dim_to_staging.assert_called_once_with(table_name)

    @mock.patch.object(LifullCampaigns, '_load_fact_to_staging')
    def test__load_table_fact(self, mock__load_fact_to_staging, lifull_campaigns):
        # arrange
        table_name = 'fact_foo_bar'

        # act
        lifull_campaigns._load_table(table_name)

        # assert
        mock__load_fact_to_staging.assert_called_once_with(table_name)

    def test__load_table_not_fact_nor_dim(self, lifull_campaigns):
        # arrange
        table_name = mock.ANY

        # act
        with pytest.raises(AttributeError):
            lifull_campaigns._load_table(table_name)

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    def test__load_dim_to_staging(self, mock_get_query_from_file_name, lifull_campaigns):
        # arrange
        table_name = mock.ANY
        expected_full_load_query = 'marketing/lifull_campaigns/clean_to_staging/{}.sql'.format(table_name)

        # act
        lifull_campaigns._load_dim_to_staging(table_name)

        # assert
        mock_get_query_from_file_name.assert_called_once()
        mock_get_query_from_file_name.assert_called_with('{}/{}'.format(DATALAKE_QUERIES_DIR, expected_full_load_query))

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(LifullCampaigns, '_is_prod_table_empty')
    def test__load_fact_to_staging_empty(self, mock__is_prod_table_empty, mock_get_query_from_file_name,
                                         lifull_campaigns):
        # arrange
        table_name = mock.ANY
        expected_full_load_query = 'marketing/lifull_campaigns/clean_to_staging/{}.sql'.format(table_name)
        mock__is_prod_table_empty.return_value = True

        # act
        lifull_campaigns._load_fact_to_staging(table_name)

        # assert
        mock_get_query_from_file_name.assert_called_once()
        mock_get_query_from_file_name.assert_called_with('{}/{}'.format(DATALAKE_QUERIES_DIR, expected_full_load_query))

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(LifullCampaigns, '_is_prod_table_empty')
    @mock.patch.object(BaseETL, 'execute_command')
    def test__load_fact_to_staging_not_empty(self, mock_execute_command, mock__is_prod_table_empty,
                                             mock_get_query_from_file_name, lifull_campaigns):
        # arrange
        table_name = mock.ANY
        expected_full_load_query = 'marketing/lifull_campaigns/clean_to_staging/{}.sql'.format(table_name)
        mock__is_prod_table_empty.return_value = False
        int_date = int(lifull_campaigns.execution_date.strftime("%Y%m%d"))
        expected_args = [({'command': 'DELETE FROM staging.<ANY> where sk_date = {0}'.format(int_date), 'commit': True,
                           'db_enum': EnumDB.BI_DW, 'encoding': 'utf-8'},),
                         ({'command': 'DELETE FROM marketing.<ANY> where sk_date = {0}'.format(int_date),
                           'commit': True, 'db_enum': EnumDB.BI_DW, 'encoding': 'utf-8'},)]

        # act
        lifull_campaigns._load_fact_to_staging(table_name)

        # assert
        mock_get_query_from_file_name.assert_called_once()
        mock_get_query_from_file_name.assert_called_with('{}/{}'.format(DATALAKE_QUERIES_DIR, expected_full_load_query))
        assert mock_execute_command.call_count == 2
        assert mock_execute_command.call_args_list == expected_args

    @mock.patch.object(LifullCampaigns, '_load_to_prod')
    def test_load_to_prod(self, mock__load_to_prod, lifull_campaigns):
        # arrange
        table_name = 'dim_table'

        # act
        lifull_campaigns.load_to_prod(table_name)

        # assert
        mock__load_to_prod.assert_called_once_with(table_name)

    @mock.patch.object(LifullCampaigns, '_load_dim_to_staging')
    def test_load_to_prod(self, mock__load_dim_to_staging, lifull_campaigns):
        # arrange
        table_name = 'dim_{}'.format(mock.ANY)

        # act
        lifull_campaigns._load_table(table_name)

        # assert
        mock__load_dim_to_staging.assert_called_once_with(table_name)
