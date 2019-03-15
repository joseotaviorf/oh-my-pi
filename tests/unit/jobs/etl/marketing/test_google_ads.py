import mock
import pytest

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl.marketing import GoogleAds


class TestGoogleAds(object):

    @mock.patch.object(GoogleAds, '_move_to_clean')
    def test_move_campaigns_to_clean(self, mock__move_to_clean, google_ads):
        # act
        google_ads.move_campaigns_to_clean()

        # assert
        assert mock__move_to_clean.call_count == 1
        assert mock__move_to_clean.call_args[1]['table_name'] == 'marketing_google_campaigns'
        assert mock__move_to_clean.call_args[1]['sql_file_name'] == 'campaign.sql'

    @mock.patch.object(GoogleAds, '_move_to_clean')
    def test_move_keywords_to_clean(self, mock__move_to_clean, google_ads):
        # act
        google_ads.move_keywords_to_clean()

        # assert
        assert mock__move_to_clean.call_count == 1
        assert mock__move_to_clean.call_args[1]['table_name'] == 'marketing_google_keywords'
        assert mock__move_to_clean.call_args[1]['sql_file_name'] == 'keyword.sql'

    @mock.patch.object(GoogleAds, '_move_to_clean')
    def test_move_ads_to_clean(self, mock__move_to_clean, google_ads):
        # act
        google_ads.move_ads_to_clean()

        # assert
        assert mock__move_to_clean.call_count == 1
        assert mock__move_to_clean.call_args[1]['table_name'] == 'marketing_google_ads'
        assert mock__move_to_clean.call_args[1]['sql_file_name'] == 'ad.sql'

    @pytest.mark.parametrize('table',
                             ['marketing_google_ads', 'marketing_google_keywords', 'marketing_google_campaigns'])
    @mock.patch.object(GoogleAds, '_load_to_pre_staging')
    def test_load_to_pre_staging(self, mock__load_to_pre_staging, table, google_ads):
        # arrange
        clean_table = table
        prod_table = 'prod_table'
        accounts = ['default1', 'default2', 'default3']

        # act
        google_ads.load_to_pre_staging(clean_table, prod_table, accounts)

        # assert
        assert mock__load_to_pre_staging.call_count == 1
        assert mock__load_to_pre_staging.call_args[0][0] == clean_table
        assert mock__load_to_pre_staging.call_args[0][1] == prod_table
        assert mock__load_to_pre_staging.call_args[0][2] == accounts

    @mock.patch.object(GoogleAds, '_load_table', return_value='select * from table')
    @mock.patch.object(GoogleAds, '_load_to_staging')
    def test_load_to_staging(self, mock__load_to_staging, mock_load_table, google_ads):
        # arrange
        dw_table_name = 'dw_table_name'

        google_ads.load_to_staging(dw_table_name)

        assert mock__load_to_staging.call_count == 1
        assert mock__load_to_staging.call_args[0][0] == dw_table_name
        assert mock__load_to_staging.call_args[0][1] == 'select * from table'
        assert mock_load_table.call_count == 1

    @mock.patch.object(GoogleAds, '_load_dim_to_staging')
    def test__load_table_with_dim_table(self, mock__load_dim_to_staging, google_ads):
        # arrange
        table_name = 'dim_table'

        # act
        google_ads._load_table(table_name)

        # assert
        assert mock__load_dim_to_staging.call_count == 1
        assert mock__load_dim_to_staging.call_args[0][0] == table_name

    @mock.patch.object(GoogleAds, '_load_fact_to_staging')
    def test__load_table_with_fact_table(self, mock__load_fact_to_staging, google_ads):
        # arrange
        table_name = 'fact_table'

        # act
        google_ads._load_table(table_name)

        # assert
        assert mock__load_fact_to_staging.call_count == 1
        assert mock__load_fact_to_staging.call_args[0][0] == table_name

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    def test__load_dim_to_staging(self, mock_get_query_from_file_name, google_ads):
        # arrange
        table_name = 'table'

        # act
        google_ads._load_dim_to_staging(table_name)

        # assert
        assert mock_get_query_from_file_name.call_count == 1

    @mock.patch.object(GoogleAds, '_is_prod_table_empty', return_value=True)
    @mock.patch.object(BaseETL, 'get_query_from_file_name', return_value='table')
    def test__load_fact_to_staging_with_prod_table_empty(self, mock_get_query_from_file_name,
                                                         mock__is_prod_table_empty,
                                                         google_ads):
        # arrange
        table_name = 'table'

        # act
        google_ads._load_fact_to_staging(table_name)

        # assert
        assert mock_get_query_from_file_name.call_count == 4
        assert mock__is_prod_table_empty.call_count == 1

    @mock.patch.object(BaseETL, 'execute_command')
    @mock.patch.object(GoogleAds, '_is_prod_table_empty', return_value=False)
    @mock.patch.object(BaseETL, 'get_query_from_file_name', return_value='table')
    def test__load_fact_to_staging_with_prod_table_not_empty(self, mock_get_query_from_file_name,
                                                             mock__is_prod_table_empty,
                                                             mock_execute_command,
                                                             google_ads):
        # arrange
        table_name = 'table'
        expect_delete_query_prod = 'DELETE FROM marketing.table where sk_date = 20180101'
        expect_delete_query_staging = 'DELETE FROM staging.table where sk_date = 20180101'

        # act
        google_ads._load_fact_to_staging(table_name)

        # assert
        assert mock_get_query_from_file_name.call_count == 4
        assert mock__is_prod_table_empty.call_count == 1
        assert mock_execute_command.call_count == 2
        assert mock_execute_command.call_args_list[0][1]['command'] == expect_delete_query_staging
        assert mock_execute_command.call_args_list[1][1]['command'] == expect_delete_query_prod

    @mock.patch.object(GoogleAds, '_load_to_prod')
    def test_load_to_prod(self, mock__load_to_prod, google_ads):
        # arrange
        table_name = 'table'

        # act
        google_ads.load_to_prod(table_name)

        # assert
        assert mock__load_to_prod.call_count == 1
        assert mock__load_to_prod.call_args[0][0] == table_name
