from datetime import date

import bietlejuice.jobs.base.new_base_etl as utils
import mock
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.base_etl import EnumDB
from bietlejuice.jobs.dags import SOURCE_QUERIES_DIR
from bietlejuice.jobs.etl.affiliate import AffiliateETL


class TestAffiliateETL(object):
    @mock.patch.object(BaseETL, 'execute_command')
    def test_delete_daily_rows(self, mock_execute_command, affiliate_etl):
        # arrange
        db_enum = mock.ANY
        schema = mock.ANY
        table_name = mock.ANY
        date_column = mock.ANY
        value = mock.ANY

        # act
        affiliate_etl.delete_daily_rows(db_enum, schema, table_name, date_column, value)

        # assert
        mock_execute_command.assert_called_once_with(
            command="delete from {}.{} where date({}) = date('{}')".format(schema, table_name, date_column, value),
            db_enum=db_enum,
            encoding='utf-8',
            commit=True)

    @mock.patch.object(BaseETL, 'execute_command')
    def test_delete_monthly_rows(self, mock_execute_command, affiliate_etl):
        # arrange
        db_enum = mock.ANY
        schema = mock.ANY
        table_name = mock.ANY
        date_column = mock.ANY
        execution_date = date(2019, 1, 1)
        expected_ym = str(execution_date.strftime('%Y%m'))

        # act
        affiliate_etl.delete_monthly_rows(db_enum, schema, table_name, date_column, execution_date)

        # assert
        mock_execute_command.assert_called_once_with(
            command="delete from {}.{} where {} = {}".format(schema, table_name, date_column, expected_ym),
            db_enum=db_enum,
            encoding='utf-8',
            commit=True)

    @mock.patch.object(BaseETL, 'get_query_from_file_name', return_value='{str_date}')
    @mock.patch.object(AffiliateETL, 'delete_daily_rows')
    @mock.patch.object(utils, 'extract_query_dim_from_ebdb_to_ods')
    def test_extract_query_from_ebdb_to_ods(self, mock_extract_query_dim_from_ebdb_to_ods, mock_delete_daily_rows,
                                            mock_get_query_from_file_name, affiliate_etl):
        # arrange
        schema = mock.ANY
        table_name = mock.ANY
        date_column = mock.ANY
        execution_date = mock.ANY
        s3_bucket = mock.ANY
        file_path = '{}/ebdb/affiliates/{}.sql'.format(SOURCE_QUERIES_DIR, table_name)

        # act
        affiliate_etl.extract_query_from_ebdb_to_ods(s3_bucket, schema, table_name, date_column, execution_date)

        # assert
        mock_delete_daily_rows.assert_called_once_with(db_enum=EnumDB.BI_ODS, schema=schema, table_name=table_name,
                                                       date_column=date_column, value=str(execution_date))
        mock_get_query_from_file_name.assert_called_once_with(file_name=file_path)
        mock_extract_query_dim_from_ebdb_to_ods.assert_called_once_with(
            dim_name=table_name,
            bucket=s3_bucket,
            command=str(execution_date),
            table_name='{}.{}'.format(schema, table_name),
            append=True
        )

    @mock.patch.object(AffiliateETL, 'delete_monthly_rows')
    @mock.patch.object(BaseETL, 'move_file_query_data_to_db', return_value='{str_date}')
    def test_append_monthly_data_to_dw_table(self, mock_move_file_query_data_to_db, mock_delete_monthly_rows,
                                             affiliate_etl):
        # arrange
        file_name = mock.ANY
        schema = mock.ANY
        table_name = mock.ANY
        date_column = mock.ANY
        execution_date = mock.ANY

        # act
        affiliate_etl.append_monthly_data_to_dw_table(file_name, schema, table_name, execution_date, date_column)

        # assert
        mock_delete_monthly_rows.assert_called_once_with(db_enum=EnumDB.BI_DW, schema=schema, table_name=table_name,
                                                         date_column=date_column, execution_date=execution_date)
        mock_move_file_query_data_to_db.assert_called_once_with(schema=schema,
                                                                file_name=file_name,
                                                                table_name=table_name,
                                                                append=True,
                                                                db_enum_source=EnumDB.BI_DW,
                                                                db_enum_destination=EnumDB.BI_DW,
                                                                query_params_dict={'execution_date': execution_date}
                                                                )
