from collections import OrderedDict
from datetime import datetime

import mock
import pandas as pd
import petl
import pytest
from mock import MagicMock, Mock
from pytest import raises

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl.marketing import ClassifiedsCosts


class TestClassifiedsCosts(object):

    @mock.patch.object(ClassifiedsCosts, '_save_to_s3')
    @mock.patch.object(ClassifiedsCosts, '_get_google_sheets_data')
    def test_move_classifieds_costs_to_raw(self, mock__get_google_sheets_data,
                                           mock__save_to_s3, classifieds_costs):
        # arrange
        mock_df_gsheets = Mock()
        mock__get_google_sheets_data.return_value = mock_df_gsheets

        # act
        classifieds_costs.move_classifieds_costs_to_raw()

        # assert
        mock__get_google_sheets_data.assert_called_once_with()
        mock__save_to_s3.assert_called_once_with(mock_df_gsheets)

    @pytest.mark.parametrize('date, expected_date',
                             [(datetime(2025, 12, 31), datetime(2025, 12, 1)),
                              (datetime(2016, 3, 24), datetime(2016, 3, 1)),
                              (datetime(2012, 2, 29), datetime(2012, 2, 1)),
                              ])
    def test_force_month_first_day(self, date, expected_date, classifieds_costs):
        # act
        new_execution_date = classifieds_costs._force_month_first_day(date)

        # assert
        assert new_execution_date == expected_date

    @mock.patch.object(ClassifiedsCosts, '_get_extra_config')
    @mock.patch('bietlejuice.jobs.etl.marketing.classifieds_costs.GoogleSheetsClient')
    def test_get_google_sheets_data(self, mock_gsheets_client, mock__get_extra_config,
                                    classifieds_costs):
        # arrange
        mock_df = Mock()
        mock_gsheets_client_obj = Mock()
        mock_gsheets_client_obj.get_dataframe_from_sheet.return_value = mock_df
        mock_gsheets_client.return_value = mock_gsheets_client_obj
        mock__get_extra_config.return_value = mock.ANY

        # act
        df = classifieds_costs._get_google_sheets_data()

        # assert
        assert df == mock_df

    def test_get_extra_config(self, classifieds_costs):
        # arrange
        classifieds_costs.funnel_side = 'demand'

        # act
        side = classifieds_costs._get_extra_config('funnel_side')

        # assert
        assert side == 'demand'

    def test_get_extra_config_empty(self, classifieds_costs):
        # arrange
        classifieds_costs.funnel_side = ''

        # assert
        with raises(ValueError):
            # act
            side = classifieds_costs._get_extra_config('funnel_side')

    @mock.patch.object(BaseETL, 'obj_to_s3')
    def test_save_to_s3_with_empty_data(self, mock__obj_to_s3, classifieds_costs):
        # act
        classifieds_costs._save_to_s3([])

        # assert
        mock__obj_to_s3.assert_not_called()

    @mock.patch.object(BaseETL, 'obj_to_s3')
    @mock.patch('bietlejuice.jobs.etl.marketing.classifieds_costs.BytesIO')
    def test_save_to_s3(self, mock__bytes_io, mock__obj_to_s3, classifieds_costs):
        # arrange
        mocked_bytes_io = MagicMock()
        mock__bytes_io.return_value = mocked_bytes_io

        mock_pendulum = Mock()
        mock_pendulum.strftime = MagicMock(return_value='2020-09-22')
        classifieds_costs.execution_date = mock_pendulum

        expected_s3_file_path = 'raw/marketing/classifieds_costs/side/acc=default/' \
                                'dt=2020-09-22/data.gz'
        raw_data = pd.DataFrame.from_dict({'abada': ['badoo']})

        # act
        classifieds_costs._save_to_s3(raw_data)

        # assert
        mock__obj_to_s3.assert_called_with(obj_io=mocked_bytes_io,
                                           bucket=classifieds_costs.s3_bucket,
                                           file_path=expected_s3_file_path)

    @mock.patch.object(ClassifiedsCosts, '_move_to_clean')
    def test_move_classifieds_demand_costs_to_clean(self, mock__move_to_clean,
                                                    classifieds_costs):
        # act
        classifieds_costs.move_classifieds_demand_costs_to_clean()

        # assert
        raw_table_query_file = 'classifieds_demand_costs.sql'
        clean_cols = OrderedDict([
            ('medium', str),
            ('source', str),
            ('cost', str)
        ])

        mock__move_to_clean.assert_called_once()
        mock__move_to_clean.assert_called_once_with(
            table_name='marketing_demand_classifieds_costs',
            sql_file_name=raw_table_query_file,
            r_cols=clean_cols,
            c_cols=clean_cols)

    @mock.patch.object(ClassifiedsCosts, '_move_to_clean')
    def test_move_classifieds_supply_costs_to_clean(self, mock__move_to_clean,
                                                    classifieds_costs):
        # act
        classifieds_costs.move_classifieds_supply_costs_to_clean()

        # assert
        raw_table_query_file = 'classifieds_supply_costs.sql'
        clean_cols = OrderedDict([
            ('medium', str),
            ('source', str),
            ('cost', str)
        ])

        mock__move_to_clean.assert_called_once()
        mock__move_to_clean.assert_called_once_with(
            table_name='marketing_supply_classifieds_costs',
            sql_file_name=raw_table_query_file,
            r_cols=clean_cols,
            c_cols=clean_cols)

    @mock.patch.object(ClassifiedsCosts, '_get_staging_table_query')
    @mock.patch.object(ClassifiedsCosts, '_load_to_staging')
    def test_load_to_staging(self, mock__load_to_staging, mock__get_staging_table_query,
                             classifieds_costs):
        # arrange
        dw_table_name = 'dim_table_c'
        query = 'cool_query'
        mock__get_staging_table_query.return_value = query

        # act
        classifieds_costs.load_to_staging(dw_table_name)

        # assert
        mock__load_to_staging.assert_called_once_with(dw_table_name, query)

    @mock.patch.object(BaseETL, 'execute_command')
    def test__delete_fact_rows(self, mock_bulk_insert, classifieds_costs):
        # act
        classifieds_costs._delete_fact_rows('fact_crazy_table', 20190401)

        # assert
        mock_bulk_insert.assert_called_once_with(
            db_enum=EnumDB.BI_DW,
            command="DELETE FROM staging.fact_crazy_table "
                    "WHERE sk_date BETWEEN 20190401 AND 20190431",
            commit=True,
            encoding='utf-8'
        )

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(ClassifiedsCosts, '_is_staging_table_empty')
    def test__get_staging_table_query_for_dim_table(self, mock__is_staging_table_empty,
                                                    mock__get_query_from_file_name,
                                                    classifieds_costs):
        # arrange
        table_name = 'dim_table_1'
        expected_full_load_query = 'full_query'
        mock__get_query_from_file_name.return_value = expected_full_load_query

        # act
        query = classifieds_costs._get_staging_table_query(table_name)

        # assert
        mock__get_query_from_file_name.assert_called()
        assert query == expected_full_load_query

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(ClassifiedsCosts, '_is_staging_table_empty')
    @mock.patch.object(ClassifiedsCosts, '_delete_fact_rows')
    def test__get_staging_table_query_for_fact_table(self, mock__delete_fact_rows,
                                                     mock__is_staging_table_empty,
                                                     mock__get_query_from_file_name,
                                                     classifieds_costs):
        # arrange
        table_name = 'fact_table_1'
        expected_full_load_query = 'full_query'
        mock__get_query_from_file_name.return_value = expected_full_load_query
        mock__is_staging_table_empty.return_value = False
        classifieds_costs.execution_date = datetime(2010, 9, 1)

        # act
        query = classifieds_costs._get_staging_table_query(table_name)

        # assert
        mock__get_query_from_file_name.assert_called()
        assert query == expected_full_load_query + ' \nWHERE sk_date BETWEEN 20100901 AND 20100931;'

    @mock.patch.object(BaseETL, 'bulk_insert')
    @mock.patch.object(petl, 'fromdataframe')
    def test__load_to_staging(self, mock__fromdataframe, mock__bulk_insert,
                              classifieds_costs):
        # arrange
        dw_table_name = 'dim_table_q'
        staging_query = 'cool_query'
        mock_pd_df = MagicMock()
        fn = MagicMock(return_value=mock_pd_df)
        classifieds_costs.athena_client.execute_query_and_return_dataframe = fn

        df_table = MagicMock()
        mock__fromdataframe.return_value = df_table

        # act
        classifieds_costs._load_to_staging(dw_table_name, staging_query)

        # assert
        classifieds_costs.athena_client.execute_query_and_return_dataframe \
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

    @mock.patch.object(ClassifiedsCosts, '_load_to_prod')
    def test_load_to_prod(self, mock__load_to_prod, classifieds_costs):
        # arrange
        table_name = 'dim_table'

        # act
        classifieds_costs.load_to_prod(table_name)

        # assert
        mock__load_to_prod.assert_called_once_with(table_name)
