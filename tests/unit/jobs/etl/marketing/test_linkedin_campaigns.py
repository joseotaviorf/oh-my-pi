from collections import OrderedDict
from datetime import datetime

import mock
import petl
from mock import MagicMock, Mock
from pytest import raises

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl.marketing.linkedin_campaigns import LinkedInCampaigns


class TestLinkedInCampaigns(object):

    def test_get_google_drive_folder_id_with_no_folder_id(self, linkedin_campaigns):
        # assert
        with raises(RuntimeError):
            # act
            linkedin_campaigns._get_google_drive_folder_id()

    def test_get_google_drive_folder_id(self, linkedin_campaigns):
        # arrange
        linkedin_campaigns.extra_configs = {'gdrive_dir_id': '1234'}

        # act
        folder_id = linkedin_campaigns._get_google_drive_folder_id()

        # assert
        assert folder_id == '1234'

    @mock.patch("__builtin__.next")
    @mock.patch("__builtin__.open")
    def test_validate_csv_header_invalid_column(self, mock_open, mock_next,
                                                linkedin_campaigns):
        mock_next.return_value = ['invalid_col']

        # assert
        with raises(RuntimeError):
            # act
            linkedin_campaigns._validate_csv_header('tmp_filename')

    @mock.patch("__builtin__.next")
    @mock.patch("__builtin__.open")
    def test_validate_csv_header(self, mock_open, mock_next, linkedin_campaigns):
        mock_next.return_value = ['account_id', 'campaign_id', 'campaign_name']

        # act
        result = linkedin_campaigns._validate_csv_header('tmp_filename')

        # assert
        assert result

    @mock.patch('bietlejuice.jobs.etl.marketing.linkedin_campaigns.GoogleDriveClient')
    @mock.patch.object(LinkedInCampaigns, '_get_process_file')
    @mock.patch.object(LinkedInCampaigns, '_save_file_to_s3')
    def test_move_linkedin_campaigns_to_raw(self, mock__save_file_to_s3,
                                            mock__get_process_file,
                                            mock_google_drive_client,
                                            linkedin_campaigns):
        # arrange
        mock_google_drive_client_instance = MagicMock()
        mock_google_drive_client.return_value = mock_google_drive_client_instance

        tmp_filename = 'tmp_filename'
        mock__get_process_file.return_value = tmp_filename

        # act
        linkedin_campaigns.move_linkedin_campaigns_to_raw()

        # assert
        mock__get_process_file.assert_called_once_with(
            mock_google_drive_client_instance)
        mock__save_file_to_s3.assert_called_once_with(tmp_filename)

    @mock.patch.object(BaseETL, 'file_to_s3')
    def test__save_file_to_s3(self, mock_file_to_s3, linkedin_campaigns):
        # arrange
        tmp_filename = 'secretfile.csv'
        linkedin_campaigns.s3_bucket = 'bucket_01'
        linkedin_campaigns.execution_date = datetime(2012, 1, 2)
        linkedin_campaigns.partition_date = '2012-01-02'
        linkedin_campaigns.athena_client.add_partition = Mock()

        # act
        linkedin_campaigns._save_file_to_s3(tmp_filename)

        # assert
        mock_file_to_s3.assert_called_once_with(
            filename=tmp_filename,
            bucket_folder_path='bucket_01/raw/marketing/linkedin_campaigns/campaigns/'
                               'dt=2012-01-02')
        linkedin_campaigns.athena_client.add_partition.assert_called_once_with(
            database='datalake_raw',
            table_name='marketing_linkedin_campaigns',
            partition="dt='2012-01-02'"
        )

    def test__validate_result_with_two_files_with_the_same_name(self,
                                                                linkedin_campaigns):
        # arrange
        elements = ['a', 'b']

        # assert
        with raises(RuntimeError):
            # act
            linkedin_campaigns._validate_result(elements)

    def test__validate_result_with_no_file_found(self, linkedin_campaigns):
        # assert
        with raises(RuntimeError):
            # act
            linkedin_campaigns._validate_result([])

    def test__validate_result(self, linkedin_campaigns):
        # act
        result = linkedin_campaigns._validate_result(['a'])

        # assert
        assert result

    @mock.patch.object(LinkedInCampaigns, '_validate_csv_header')
    @mock.patch.object(LinkedInCampaigns, '_get_google_drive_folder_id')
    @mock.patch.object(LinkedInCampaigns, '_validate_result')
    def test__get_process_file(self, mock__validate_result,
                               mock_get_google_drive_folder_id,
                               mock__validate_csv_header, linkedin_campaigns):
        # arrange
        mock_get_google_drive_folder_id.return_value = ''
        mock_file = [{'id': 1}]
        google_drive_client = MagicMock()
        google_drive_client.list_files.return_value = mock_file

        google_drive_client.download_file.return_value = 'tmp_filename'

        # act
        file = linkedin_campaigns._get_process_file(google_drive_client)

        # assert
        assert 'tmp_filename' == file
        mock__validate_result.assert_called_once_with(mock_file)
        google_drive_client.download_file.assert_called_once_with(
            file_id=mock_file[0]['id'],
            path='/tmp')
        mock__validate_csv_header.assert_called_once_with('/tmp/tmp_filename')

    @mock.patch.object(LinkedInCampaigns, '_move_to_clean')
    def test_move_linkedin_campaigns_to_clean(self, mock__move_to_clean,
                                              linkedin_campaigns):
        # act
        linkedin_campaigns.move_linkedin_campaigns_to_clean()

        # assert
        raw_table_query_file = 'campaigns.sql'
        raw_cols = OrderedDict([
            ('id_account', str),
            ('id_campaign', str),
            ('campaign_name', str),
            ('impressions', str),
            ('clicks', str),
            ('ctr', str),
            ('cpc', str)
        ])

        mock__move_to_clean.assert_called_once_with(
            table_name='marketing_linkedin_campaigns',
            sql_file_name=raw_table_query_file,
            r_cols=raw_cols,
            c_cols=raw_cols)

    @mock.patch.object(LinkedInCampaigns, '_get_staging_table_query')
    @mock.patch.object(LinkedInCampaigns, '_load_to_staging')
    def test_load_to_staging(self, mock__load_to_staging, mock__get_staging_table_query,
                             linkedin_campaigns):
        # arrange
        dw_table_name = 'dim_table_c'
        query = 'cool_query'
        mock__get_staging_table_query.return_value = query

        # act
        linkedin_campaigns.load_to_staging(dw_table_name)

        # assert
        mock__load_to_staging.assert_called_once_with(dw_table_name, query)

    @mock.patch.object(BaseETL, 'execute_command')
    def test__delete_fact_rows(self, mock_bulk_insert, linkedin_campaigns):
        # act
        linkedin_campaigns._delete_fact_rows('fact_crazy_table', '20190401')

        # assert
        mock_bulk_insert.assert_called_once_with(
            db_enum=EnumDB.BI_DW,
            command="DELETE FROM staging.fact_crazy_table WHERE sk_date = 20190401",
            commit=True,
            encoding='utf-8'
        )

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(LinkedInCampaigns, '_is_staging_table_empty')
    def test__get_staging_table_query_for_dim_table(self, mock__is_staging_table_empty,
                                                    mock__get_query_from_file_name,
                                                    linkedin_campaigns):
        # arrange
        table_name = 'dim_table_1'
        expected_full_load_query = 'full_query'
        mock__get_query_from_file_name.return_value = expected_full_load_query

        # act
        query = linkedin_campaigns._get_staging_table_query(table_name)

        # assert
        mock__get_query_from_file_name.assert_called()
        assert query == expected_full_load_query

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(LinkedInCampaigns, '_is_staging_table_empty')
    @mock.patch.object(LinkedInCampaigns, '_delete_fact_rows')
    def test__get_staging_table_query_for_fact_table(self, mock__delete_fact_rows,
                                                     mock__is_staging_table_empty,
                                                     mock__get_query_from_file_name,
                                                     linkedin_campaigns):
        # arrange
        table_name = 'fact_table_1'
        expected_full_load_query = 'full_query'
        mock__get_query_from_file_name.return_value = expected_full_load_query
        mock__is_staging_table_empty.return_value = False
        linkedin_campaigns.execution_date = datetime(2010, 9, 22)

        # act
        query = linkedin_campaigns._get_staging_table_query(table_name)

        # assert
        mock__get_query_from_file_name.assert_called()
        assert query == expected_full_load_query + ' \nWHERE sk_date = 20100922;'

    @mock.patch.object(BaseETL, 'bulk_insert')
    @mock.patch.object(petl, 'fromdataframe')
    def test__load_to_staging(self, mock__fromdataframe, mock__bulk_insert,
                              linkedin_campaigns):
        # arrange
        dw_table_name = 'dim_table_q'
        staging_query = 'cool_query'
        mock_pd_df = MagicMock()
        fn = MagicMock(return_value=mock_pd_df)
        linkedin_campaigns.athena_client.execute_query_and_return_dataframe = fn

        df_table = MagicMock()
        mock__fromdataframe.return_value = df_table

        # act
        linkedin_campaigns._load_to_staging(dw_table_name, staging_query)

        # assert
        linkedin_campaigns.athena_client.execute_query_and_return_dataframe \
            .assert_called_once_with(sql=staging_query)
        mock__fromdataframe.assert_called_once_with(df=mock_pd_df)
        mock__bulk_insert.assert_called_once_with(
            table=df_table,
            table_name='staging.dim_table_q',
            db_enum=EnumDB.BI_DW,
            encoding='utf-8',
            append=False,
            commit=True
        )
