from collections import OrderedDict

import mock
import pandas as pd
import pytest
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl.marketing import Marketing
from qa_python_utils.aws.athena import AthenaClient


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
        expect_dt_partition = "dt_created='2018-01-01', acc='account'"

        # act
        mkt_acc_integration._move_to_clean(table_name, sql_file_name, r_cols)

        # assert
        assert expect_query_path in mock_get_query_from_file_name.call_args[0][0]
        assert mock_get_query_from_file_name.call_count == 1
        assert mock_add_partition.call_args[1]['partition'] == expect_dt_partition
        assert mock_add_partition.call_count == 2
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

    @mock.patch.object(Marketing, '_upsert_into_dw')
    @mock.patch.object(Marketing, '_is_prod_table_empty', return_value=True)
    def test__load_to_prod_with_table_empty(self, mock__is_prod_table_empty, mock__upsert_into_dw, marketing):
        # arrange
        table_name = 'fact_table'
        expected_upsert_query = 'SELECT DISTINCT * FROM staging.fact_table'

        # act
        marketing._load_to_prod(table_name)

        # assert
        assert mock__is_prod_table_empty.call_count == 1
        assert mock__is_prod_table_empty.call_args[0][0] == table_name
        assert mock__upsert_into_dw.call_count == 1
        assert mock__upsert_into_dw.call_args[0][0] == expected_upsert_query
        assert mock__upsert_into_dw.call_args[0][1] == table_name
        assert mock__upsert_into_dw.call_args[0][2] == 'marketing'

    @mock.patch.object(Marketing, '_delete_old_entries')
    @mock.patch.object(BaseETL, 'get_query_from_file_name', return_value='delete * from fact_table')
    @mock.patch.object(Marketing, '_upsert_into_dw')
    @mock.patch.object(Marketing, '_is_prod_table_empty', return_value=False)
    def test__load_to_prod_with_fact_table_and_not_empty(self, mock__is_prod_table_empty, mock__upsert_into_dw,
                                                         mock_get_query_from_file_name,
                                                         mock__delete_old_entries,
                                                         marketing):
        # arrange
        table_name = 'fact_table'
        expected_upsert_query = 'SELECT DISTINCT * FROM staging.fact_table \nwhere sk_date = 20180101;'

        # act
        marketing._load_to_prod(table_name)

        # assert
        assert mock__is_prod_table_empty.call_count == 1
        assert mock__is_prod_table_empty.call_args[0][0] == table_name
        assert mock_get_query_from_file_name.call_count == 1
        assert mock__upsert_into_dw.call_count == 1
        assert mock__delete_old_entries.call_count == 1
        assert mock__delete_old_entries.call_args[1] == {
            'table_name': table_name,
            'delete_query': 'delete * from fact_table'
        }
        assert mock__upsert_into_dw.call_args[0][0] == expected_upsert_query
        assert mock__upsert_into_dw.call_args[0][1] == table_name
        assert mock__upsert_into_dw.call_args[0][2] == 'marketing'

    @mock.patch.object(Marketing, '_delete_old_entries')
    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(Marketing, '_upsert_into_dw')
    @mock.patch.object(Marketing, '_is_prod_table_empty', return_value=False)
    def test__load_to_prod_with_dim_table_and_not_empty(self, mock__is_prod_table_empty, mock__upsert_into_dw,
                                                        mock_get_query_from_file_name,
                                                        mock__delete_old_entries,
                                                        marketing):
        # arrange
        table_name = 'dim_trovit_campaign'

        # act
        marketing._load_to_prod(table_name)

        # assert
        assert mock__is_prod_table_empty.call_count == 1
        assert mock__is_prod_table_empty.call_args[0][0] == table_name
        assert mock_get_query_from_file_name.call_count == 1
        assert mock__upsert_into_dw.call_count == 1
        assert mock__delete_old_entries.call_count == 1
        assert mock__delete_old_entries.call_args[1]['table_name'] == table_name
        assert mock__upsert_into_dw.call_args[0][1] == table_name
        assert mock__upsert_into_dw.call_args[0][2] == 'marketing'

    @mock.patch.object(BaseETL, 'bulk_insert')
    @mock.patch.object(BaseETL, 'from_db_query')
    def test_upsert_into_dw_with(self, mock_from_db_query, mock_bulk_insert, marketing):
        # arrange
        upsert_query = 'select * from table'
        table_name = 'table'
        schema = 'marketing'

        # act
        marketing._upsert_into_dw(upsert_query, table_name, schema)

        # assert
        assert mock_from_db_query.call_count == 1
        assert mock_bulk_insert.call_count == 1
        assert mock_from_db_query.call_args[1]['query'] == upsert_query

    @mock.patch.object(BaseETL, 'from_db_query')
    def test__is_staging_table_empty(self, mock_from_db_query, marketing):
        # act
        marketing._is_staging_table_empty(table_name='table_staging')

        # assert
        mock_from_db_query.assert_called_once_with(
            db_enum=EnumDB.BI_DW,
            query="select 1 from staging.table_staging limit 1",
            encoding="utf-8"
        )

    @mock.patch.object(BaseETL, 'from_db_query')
    def test__is_prod_table_empty(self, mock_from_db_query, marketing):
        # act
        marketing._is_prod_table_empty(table_name='table_prod')

        # assert
        mock_from_db_query.assert_called_once_with(
            db_enum=EnumDB.BI_DW,
            query="select 1 from marketing.table_prod limit 1",
            encoding="utf-8"
        )

    @mock.patch.object(BaseETL, 'execute_command')
    def test__delete_old_entries(self, mock_execute_command, marketing):
        # arrange
        table_name = 'dim_trovit_campaign'
        delete_query = "select * from {table_name} where {sk_field}"

        # act
        marketing._delete_old_entries(table_name, delete_query)

        # assert
        assert mock_execute_command.call_count == 1

    @mock.patch.object(AthenaClient, 'add_partition')
    def test_update_table_partitions_with_one_call(self, mock_add_partition, marketing):
        # arrange
        schema_name = 'test'
        table = 'test_table'
        accounts = ['default']

        # act
        marketing._update_table_partitions(schema_name, table, accounts)

        # assert
        assert mock_add_partition.call_count == 1
        assert mock_add_partition.call_args[1] == {
            'database': schema_name,
            'table_name': table,
            'partition': "dt_created='2018-01-01', acc='default'"
        }

    @mock.patch.object(AthenaClient, 'add_partition')
    def test_update_table_partitions_with_two_calls(self, mock_add_partition, marketing):
        # arrange
        schema_name = 'test'
        table = 'test_table'
        accounts = ['default1', 'default2']

        # act
        marketing._update_table_partitions(schema_name, table, accounts)

        # assert
        assert mock_add_partition.call_count == 2

    @pytest.mark.parametrize('df_return', [pd.DataFrame(data=[False], columns=['']), False, mock.ANY])
    @mock.patch.object(AthenaClient, 'execute_file_query_and_return_dataframe')
    def test__validate_data_with_previous_execution_exception(self, mock_execute_file_query_and_return_dataframe,
                                                              df_return, marketing):
        # arrange
        table_name = mock.ANY
        mock_execute_file_query_and_return_dataframe.return_value = df_return

        # act & assert
        with pytest.raises(ValueError):
            marketing._validate_data_with_previous_execution(table_name)

    @mock.patch.object(AthenaClient, 'execute_file_query_and_return_dataframe',
                       return_value=pd.DataFrame(data=[True], columns=['']))
    def test__validate_data_with_previous_execution_correct_validation(self,
                                                                       mock_execute_file_query_and_return_dataframe,
                                                                       marketing):
        # arrange
        table_name = 'lorem ipsum'

        # act
        marketing._validate_data_with_previous_execution(table_name)

        # assert
        assert mock_execute_file_query_and_return_dataframe.call_count == 1
        assert mock_execute_file_query_and_return_dataframe.call_args[1]['query_params']['table_name'] == table_name
