import mock
import pandas as pd
from collections import OrderedDict
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl.marketing.marketing import Marketing


class TestMarketing(object):

    @mock.patch.object(AthenaClient, 'add_partition')
    @mock.patch.object(AthenaClient, 'create_parquet_from_query')
    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    def test_move_to_clean(self, mock_get_query_from_file_name, mock_create_parquet_from_query, mock_add_partition,
                           mkt_acc_integration):
        # arrange
        table_name = 'table'
        sql_file_name = 'sql'
        r_cols = OrderedDict([
            ('col1', str),
            ('col2', str)
        ])
        expect_key = 'clean/marketing/integration/table/acc=account/dt_created=2018-01-01/2018-01-01.parquet'
        expect_query_path = '/marketing/integration/raw_to_clean/sql'
        expect_dt_partition = "dt='2018-01-01', acc='account'"

        # act
        mkt_acc_integration._move_to_clean(table_name, sql_file_name, r_cols)

        # assert
        assert expect_query_path in mock_get_query_from_file_name.call_args[0][0]
        assert mock_get_query_from_file_name.call_count == 1
        assert mock_add_partition.call_args[1]['partition'] == expect_dt_partition
        assert mock_add_partition.call_count == 1
        assert mock_create_parquet_from_query.call_args[1]['key'] == expect_key
        assert mock_create_parquet_from_query.call_count == 1

    @mock.patch.object(BaseETL, 'bulk_insert')
    @mock.patch.object(Marketing, '_is_prod_table_empty', return_value=True)
    @mock.patch.object(AthenaClient, 'execute_raw_query')
    @mock.patch.object(AthenaClient, 'execute_query_and_return_dataframe')
    @mock.patch.object(BaseETL, 'truncate_table')
    def test__load_to_pre_staging_with_prod_table_empty(self, mock_truncate_table,
                                                        mock_execute_query_and_return_dataframe,
                                                        mock_execute_raw_query,
                                                        mock__is_prod_table_empty,
                                                        mock_bulk_insert,
                                                        mkt_acc_integration):
        # arrange
        clean_table = 'marketing'
        prod_table = 'fact_marketing'
        accounts = ['acc1', 'acc2']
        table_schema = {
            'foo': int,
            'bar': bool
        }
        expect_pre_staging_query = 'select distinct * from datalake_clean.marketing'
        expect_load_partitions_query = 'msck repair table datalake_clean.marketing'

        # mocks
        mock_execute_query_and_return_dataframe.return_value = pd.DataFrame.from_dict(
            [{'foo': '1', 'bar': 'true'}, {'foo': '2', 'bar': 'false'}])

        # act
        mkt_acc_integration._load_to_pre_staging(clean_table, prod_table, accounts, table_schema)

        # assert
        assert mock_truncate_table.call_count == 1
        assert mock__is_prod_table_empty.call_count == 1
        assert mock_execute_raw_query.call_count == 1
        assert mock_bulk_insert.call_count == 1
        assert mock_execute_raw_query.call_args[0][0] == expect_load_partitions_query
        assert mock_execute_query_and_return_dataframe.call_count == 1
        assert mock_execute_query_and_return_dataframe.call_args[1]['sql'] == expect_pre_staging_query

    @mock.patch.object(BaseETL, 'bulk_insert')
    @mock.patch.object(Marketing, '_is_prod_table_empty', return_value=False)
    @mock.patch.object(Marketing, '_update_table_partitions')
    @mock.patch.object(AthenaClient, 'execute_query_and_return_dataframe')
    @mock.patch.object(BaseETL, 'truncate_table')
    def test__load_to_pre_staging_with_prod_table_not_empty(self, mock_truncate_table,
                                                            mock_execute_query_and_return_dataframe,
                                                            mock__update_table_partitions,
                                                            mock__is_prod_table_empty,
                                                            mock_bulk_insert,
                                                            mkt_acc_integration):
        # arrange
        clean_table = 'marketing'
        prod_table = 'fact_marketing'
        accounts = ['acc1', 'acc2']
        table_schema = {
            'foo': int,
            'bar': bool
        }
        expect_pre_staging_query = "select distinct * from datalake_clean.marketing\nwhere dt_created = '2018-01-01';"

        # mocks
        mock_execute_query_and_return_dataframe.return_value = pd.DataFrame.from_dict(
            [{'foo': '1', 'bar': 'true'}, {'foo': '2', 'bar': 'false'}])

        # act
        mkt_acc_integration._load_to_pre_staging(clean_table, prod_table, accounts, table_schema)

        # assert
        assert mock_truncate_table.call_count == 1
        assert mock__is_prod_table_empty.call_count == 1
        assert mock__update_table_partitions.call_count == 1
        assert mock__update_table_partitions.call_args[0][0] == 'datalake_clean'
        assert mock__update_table_partitions.call_args[0][1] == clean_table
        assert mock__update_table_partitions.call_args[0][2] == accounts
        assert mock_bulk_insert.call_count == 1
        assert mock_execute_query_and_return_dataframe.call_count == 1
        assert mock_execute_query_and_return_dataframe.call_args[1]['sql'] == expect_pre_staging_query

    @mock.patch.object(BaseETL, 'bulk_insert')
    @mock.patch.object(BaseETL, 'from_db_query', return_value=pd.DataFrame(['a', 'b']))
    @mock.patch.object(BaseETL, 'truncate_table')
    def test__load_to_staging(self, mock_truncate_table, mock_from_db_query, mock_bulk_insert, marketing):
        # arrange
        dw_table_name = 'datawarehouse_table'
        staging_query = 'select * from staging.datawarehouse_table'

        # act
        marketing._load_to_staging(dw_table_name, staging_query)

        # assert
        assert mock_truncate_table.call_count == 1
        assert mock_from_db_query.call_count == 1
        assert mock_bulk_insert.call_count == 1
        assert mock_truncate_table.call_args[1]['table_name'] == dw_table_name
        assert mock_truncate_table.call_args[1]['schema'] == 'staging'
        assert mock_from_db_query.call_args[1]['query'] == staging_query
        assert mock_bulk_insert.call_args[1]['table_name'] == 'staging.{}'.format(dw_table_name)
