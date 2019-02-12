import mock
import pytest
from collections import OrderedDict
from pandas import DataFrame
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR, DW_QUERIES_DIR
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
        assert mock_add_partition.call_args[1]['partition'] == "dt_extraction='2018-01-01'"
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
        final_query = query + " \n where dt='2018-01-01'"
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
        assert mock_add_partition.call_args_list[0][1]['partition'] == "dt='2018-01-01'"
        assert mock_add_partition.call_args_list[1][1]['table_name'] == 'zendesk_{}'.format(table_name)
        assert mock_add_partition.call_args_list[1][1]['partition'] == "dt_extraction='2018-01-01'"
        assert mock_create_parquet_from_query.call_count == 1
        assert mock_create_parquet_from_query.call_args[1]['query'] == final_query
        assert mock_create_parquet_from_query.call_args[1]['key'] == key
        assert mock_create_parquet_from_query.call_args[1]['raw_columns'] == raw_columns
        assert mock_is_clean_table_empty.call_count == 1

    @mock.patch.object(AthenaClient, 'execute_query_and_return_dataframe', return_value=DataFrame())
    def test__is_clean_table_empty_with_return_true(self, mock_execute_query_and_return_data_frame, zendesk):
        # arrange
        table_name = 'table'
        result_query = 'select 1 from datalake_clean.zendesk_table limit 1'

        # act
        result = zendesk._is_clean_table_empty(table_name)

        # assert
        assert result is True
        assert mock_execute_query_and_return_data_frame.call_count == 1
        assert mock_execute_query_and_return_data_frame.call_args[0][0] == result_query

    @mock.patch.object(AthenaClient, 'execute_query_and_return_dataframe', return_value=DataFrame(['foo', 'bar']))
    def test__is_clean_table_empty_with_return_false(self, mock_execute_query_and_return_data_frame, zendesk):
        # arrange
        table_name = 'table'
        result_query = 'select 1 from datalake_clean.zendesk_table limit 1'

        # act
        result = zendesk._is_clean_table_empty(table_name)

        # assert
        assert result is False
        assert mock_execute_query_and_return_data_frame.call_count == 1
        assert mock_execute_query_and_return_data_frame.call_args[0][0] == result_query

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(ZendeskETL, '_upsert_data')
    @mock.patch.object(ZendeskETL, '_delete_old_entries')
    @mock.patch.object(ZendeskETL, '_is_prod_table_empty', return_value=False)
    def test_build_prod_table_with_prod_table_not_empty_and_fact_table(self, mock__is_prod_table_empty,
                                                                       mock__delete_old_entries,
                                                                       mock__upsert_data, mock_get_query_from_file_name,
                                                                       zendesk):
        # arrange
        table_name = 'fact_ticket_metrics'
        upsert_query = "SELECT * FROM staging.zendesk_{} \nwhere sk_extraction_date = {};".format(table_name,
                                                                                                  '20180101')
        delete_query_path = '{}/zendesk/delete_old_entries.sql'.format(DW_QUERIES_DIR)

        # act
        zendesk.build_prod_table(table_name)

        # assert
        assert mock_get_query_from_file_name.call_count == 1
        assert mock_get_query_from_file_name.call_args[0][0] == delete_query_path
        assert mock__is_prod_table_empty.call_count == 1
        assert mock__delete_old_entries.call_count == 1
        assert mock__upsert_data.call_count == 1
        assert mock__upsert_data.call_args[0][0] == upsert_query
        assert mock__upsert_data.call_args[0][1] == table_name

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(ZendeskETL, '_upsert_data')
    @mock.patch.object(ZendeskETL, '_delete_old_entries')
    @mock.patch.object(ZendeskETL, '_is_prod_table_empty', return_value=False)
    def test_build_prod_table_with_prod_table_not_empty_and_dim_table(self, mock__is_prod_table_empty,
                                                                      mock__delete_old_entries,
                                                                      mock__upsert_data, mock_get_query_from_file_name,
                                                                      zendesk):
        # arrange
        table_name = 'dim_zendesk_user'
        upsert_query = "SELECT * FROM staging.zendesk_{}".format(table_name)
        delete_query_path = '{}/zendesk/delete_old_entries.sql'.format(DW_QUERIES_DIR)

        # act
        zendesk.build_prod_table(table_name)

        # assert
        assert mock_get_query_from_file_name.call_count == 1
        assert mock_get_query_from_file_name.call_args[0][0] == delete_query_path
        assert mock__is_prod_table_empty.call_count == 1
        assert mock__delete_old_entries.call_count == 1
        assert mock__upsert_data.call_count == 1
        assert mock__upsert_data.call_args[0][0] == upsert_query
        assert mock__upsert_data.call_args[0][1] == table_name

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(ZendeskETL, '_upsert_data')
    @mock.patch.object(ZendeskETL, '_delete_old_entries')
    @mock.patch.object(ZendeskETL, '_is_prod_table_empty', return_value=True)
    def test_build_prod_table_with_prod_table_empty_and_fact_table(self, mock__is_prod_table_empty,
                                                                   mock__delete_old_entries,
                                                                   mock__upsert_data, mock_get_query_from_file_name,
                                                                   zendesk):
        # arrange
        table_name = 'fact_table'
        upsert_query = "SELECT * FROM staging.zendesk_{}".format(table_name)
        delete_query_path = '{}/zendesk/delete_old_entries.sql'.format(DW_QUERIES_DIR)

        # act
        zendesk.build_prod_table(table_name)

        # assert
        assert mock_get_query_from_file_name.call_count == 1
        assert mock_get_query_from_file_name.call_args[0][0] == delete_query_path
        assert mock__is_prod_table_empty.call_count == 1
        assert mock__delete_old_entries.call_count == 0
        assert mock__upsert_data.call_count == 1
        assert mock__upsert_data.call_args[0][0] == upsert_query
        assert mock__upsert_data.call_args[0][1] == table_name

    @mock.patch.object(BaseETL, 'get_query_from_file_name', return_value="select * from table t.channel != 'api'")
    @mock.patch.object(BaseETL, 'bulk_insert')
    @mock.patch.object(AthenaClient, 'execute_query_and_return_dataframe', return_value=DataFrame())
    @mock.patch.object(ZendeskETL, '_is_prod_table_empty', return_value=True)
    def test_build_staging_table_with_prod_table_empty(self, mock__is_prod_table_empty,
                                                       mock_execute_query_and_return_dataframe,
                                                       mock_bulk_insert, mock_get_query_file_name, zendesk):
        # arrange
        table_name = 'table'
        query_path = '{}/zendesk/{}.sql'.format(DATALAKE_QUERIES_DIR, table_name)

        # act
        zendesk.build_staging_table(table_name)

        # assert
        assert mock_get_query_file_name.call_count == 1
        assert mock_get_query_file_name.call_args[0][0] == query_path
        assert mock__is_prod_table_empty.call_count == 1
        assert mock__is_prod_table_empty.call_args[0][0] == table_name
        assert mock_execute_query_and_return_dataframe.call_count == 1
        assert mock_execute_query_and_return_dataframe.call_args[0][0] == "select * from table t.channel != 'api'"
        assert mock_bulk_insert.call_count == 1
        assert mock_bulk_insert.call_args[1]['table_name'] == 'staging.zendesk_table'

    @pytest.mark.parametrize('table', ['dim_ticket', 'fact_ticket_metrics', 'dim_zendesk_user'])
    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(BaseETL, 'bulk_insert')
    @mock.patch.object(AthenaClient, 'execute_query_and_return_dataframe', return_value=DataFrame())
    @mock.patch.object(ZendeskETL, '_is_prod_table_empty', return_value=False)
    def test_build_staging_table_with_prod_table_not_empty(self, mock__is_prod_table_empty,
                                                           mock_execute_query_and_return_dataframe,
                                                           mock_bulk_insert, mock_get_query_from_file_name, table,
                                                           zendesk):
        # arrange
        table_name = table
        table_where_clause_dict = {
            'fact_ticket_metrics': 'and t.dt_extraction=\'{}\'',
            'dim_ticket': 'and t.dt_extraction=\'{}\'',
            'dim_zendesk_user': 'where t.dt_extraction=\'{}\''
        }
        table_mock_queries = {
            'fact_ticket_metrics': "select * from fact_ticket_metrics where channel != 'api' __WHERE_CLAUSE__",
            'dim_ticket': "select * from dim_ticket where channel != 'api' __WHERE_CLAUSE__",
            'dim_zendesk_user': "select * from dim_zendesk_user __WHERE_CLAUSE__"
        }
        mock_get_query_from_file_name.return_value = table_mock_queries[table_name]
        expect_table_name = 'staging.zendesk_{}'.format(table_name)
        query_path = '{}/zendesk/{}.sql'.format(DATALAKE_QUERIES_DIR, table_name)
        query = table_mock_queries[table_name].format(table_name).replace('__WHERE_CLAUSE__',
                                                                          table_where_clause_dict[table_name].format(
                                                                              '2018-01-01'))

        # act
        zendesk.build_staging_table(table_name)

        # assert
        assert mock_get_query_from_file_name.call_count == 1
        assert mock_get_query_from_file_name.call_args[0][0] == query_path
        assert mock__is_prod_table_empty.call_count == 1
        assert mock__is_prod_table_empty.call_args[0][0] == table_name
        assert mock_execute_query_and_return_dataframe.call_count == 1
        assert mock_execute_query_and_return_dataframe.call_args[0][0] == query
        assert mock_bulk_insert.call_count == 1
        assert mock_bulk_insert.call_args[1]['table_name'] == expect_table_name

    @pytest.mark.parametrize('table', ['dim_ticket', 'fact_ticket_metrics', 'dim_zendesk_user'])
    @mock.patch.object(BaseETL, 'bulk_insert')
    @mock.patch.object(BaseETL, 'get_query_from_file_name',
                       return_value='select 1 from staging.zendesk_{} __WHERE_CLAUSE__')
    @mock.patch.object(AthenaClient, 'execute_query_and_return_dataframe', return_value=DataFrame())
    @mock.patch.object(ZendeskETL, '_is_prod_table_empty', return_value=False)
    def test_build_staging_table_with_dim_ticket_not_empty(self, mock__is_prod_table_empty,
                                                           mock_execute_query_and_return_dataframe,
                                                           mock_get_query_from_file_name,
                                                           mock_bulk_insert, table, zendesk):
        # arrange
        expect_query_path = '{query_base_dir}/zendesk/{table_name}.sql'.format(
            query_base_dir=DATALAKE_QUERIES_DIR, table_name=table)
        expect_staging_table_name = 'staging.zendesk_{}'.format(table)
        expect_query = 'select 1 from staging.zendesk_{} __WHERE_CLAUSE__'.format(table) \
            .replace('__WHERE_CLAUSE__', "where t.dt_extraction='2018-01-01'")
        mock_get_query_from_file_name.return_value = expect_query

        # act
        zendesk.build_staging_table(table)

        # assert
        assert mock__is_prod_table_empty.call_count == 1
        assert mock__is_prod_table_empty.call_args[0][0] == table
        assert mock_execute_query_and_return_dataframe.call_count == 1
        assert mock_execute_query_and_return_dataframe.call_args[0][0] == expect_query
        assert mock_get_query_from_file_name.call_count == 1
        assert mock_get_query_from_file_name.call_args[0][0] == expect_query_path
        assert mock_bulk_insert.call_count == 1
        assert mock_bulk_insert.call_args[1]['table_name'] == expect_staging_table_name

    @mock.patch.object(BaseETL, 'bulk_insert')
    @mock.patch.object(BaseETL, 'from_db_query')
    def test_upsert_data(self, mock_from_db_query, mock_bulk_insert, zendesk):
        # arrange
        upsert_query = 'select * from table'
        table_name = 'table'

        # act
        zendesk._upsert_data(upsert_query, table_name)

        # assert
        assert mock_from_db_query.call_count == 1
        assert mock_from_db_query.call_args[1]['query'] == upsert_query
        assert mock_bulk_insert.call_count == 1
        assert mock_bulk_insert.call_args[1]['table_name'] == 'zendesk.{}'.format(table_name)

    @mock.patch.object(BaseETL, 'from_db_query', return_value=[1])
    def test__is_prod_table_empty_true(self, mock_from_db_query, zendesk):
        # arrange
        table_name = 'table'
        query = 'select 1 from zendesk.{} limit 1'.format(table_name)

        # act
        result = zendesk._is_prod_table_empty(table_name)

        # assert
        assert mock_from_db_query.call_count == 1
        assert mock_from_db_query.call_args[1]['query'] == query
        assert result is True

    @mock.patch.object(BaseETL, 'from_db_query', return_value=[])
    def test__is_prod_table_empty_false(self, mock_from_db_query, zendesk):
        # arrange
        table_name = 'table'
        query = 'select 1 from zendesk.{} limit 1'.format(table_name)

        # act
        result = zendesk._is_prod_table_empty(table_name)

        # assert
        assert mock_from_db_query.call_count == 1
        assert mock_from_db_query.call_args[1]['query'] == query
        assert result is False

    @mock.patch.object(BaseETL, 'execute_command')
    def test__delete_old_entries(self, mock_execute_command, zendesk):
        # arrange
        delete_query = 'delete * from table where table_a = 1'

        # act
        zendesk._delete_old_entries(delete_query)

        # assert
        assert mock_execute_command.call_count == 1
        assert mock_execute_command.call_args[1]['command'] == delete_query

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

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(ZendeskETL, '_move_to_clean')
    def test_ticket_fields_with_right_query_path(self, mock__move_to_clean, mock_get_query_from_file_name, zendesk):
        # arrange
        table_name = 'ticket_fields'

        zendesk.ticket_fields(table_name)

        assert mock_get_query_from_file_name.call_count == 1
        assert mock_get_query_from_file_name.call_args[0][0] == '{}/zendesk/ticket_fields.sql'.format(
            DATALAKE_QUERIES_DIR)
        assert mock__move_to_clean.call_count == 1

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(ZendeskETL, '_move_to_clean')
    def test_ticket_metric_events_with_right_query_path(self, mock__move_to_clean, mock_get_query_from_file_name,
                                                        zendesk):
        # arrange
        table_name = 'ticket_metric_events'

        zendesk.ticket_metric_events(table_name)

        assert mock_get_query_from_file_name.call_count == 1
        assert mock_get_query_from_file_name.call_args[0][0] == '{}/zendesk/ticket_metric_events.sql'.format(
            DATALAKE_QUERIES_DIR)
        assert mock__move_to_clean.call_count == 1

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(ZendeskETL, '_move_to_clean')
    def test_users_with_right_query_path(self, mock__move_to_clean, mock_get_query_from_file_name, zendesk):
        # arrange
        table_name = 'users'

        zendesk.users(table_name)

        assert mock_get_query_from_file_name.call_count == 1
        assert mock_get_query_from_file_name.call_args[0][0] == '{}/zendesk/users.sql'.format(
            DATALAKE_QUERIES_DIR)
        assert mock__move_to_clean.call_count == 1

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(ZendeskETL, '_move_to_clean')
    def test_groups_with_right_query_path(self, mock__move_to_clean, mock_get_query_from_file_name, zendesk):
        # arrange
        table_name = 'groups'

        zendesk.groups(table_name)

        assert mock_get_query_from_file_name.call_count == 1
        assert mock_get_query_from_file_name.call_args[0][0] == '{}/zendesk/groups.sql'.format(
            DATALAKE_QUERIES_DIR)
        assert mock__move_to_clean.call_count == 1

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(ZendeskETL, '_move_to_clean')
    def test_articles_with_right_query_path(self, mock__move_to_clean, mock_get_query_from_file_name, zendesk):
        # arrange
        table_name = 'articles'

        zendesk.articles(table_name)

        assert mock_get_query_from_file_name.call_count == 1
        assert mock_get_query_from_file_name.call_args[0][0] == '{}/zendesk/articles.sql'.format(
            DATALAKE_QUERIES_DIR)
        assert mock__move_to_clean.call_count == 1

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(ZendeskETL, '_move_to_clean')
    def test_group_memberships_with_right_query_path(self, mock__move_to_clean, mock_get_query_from_file_name, zendesk):
        # arrange
        table_name = 'group_memberships'

        zendesk.group_memberships(table_name)

        assert mock_get_query_from_file_name.call_count == 1
        assert mock_get_query_from_file_name.call_args[0][0] == '{}/zendesk/group_memberships.sql'.format(
            DATALAKE_QUERIES_DIR)
        assert mock__move_to_clean.call_count == 1

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(ZendeskETL, '_move_to_clean')
    def test_ticket_events_with_right_query_path(self, mock__move_to_clean, mock_get_query_from_file_name, zendesk):
        # arrange
        table_name = 'ticket_events'

        zendesk.ticket_events(table_name)

        assert mock_get_query_from_file_name.call_count == 1
        assert mock_get_query_from_file_name.call_args[0][0] == '{}/zendesk/ticket_events.sql'.format(
            DATALAKE_QUERIES_DIR)
        assert mock__move_to_clean.call_count == 1
