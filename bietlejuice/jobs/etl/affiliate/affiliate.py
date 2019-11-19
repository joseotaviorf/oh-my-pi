import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.base_etl import EnumDB
from bietlejuice.jobs.dags import SOURCE_QUERIES_DIR
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('Affiliate_ETL')


class AffiliateETL(object):

    @staticmethod
    @logger
    def delete_daily_rows(db_enum, schema, table_name, date_column, value):
        BaseETL.execute_command(
            command="delete from {}.{} where date({}) = date('{}')".format(schema, table_name, date_column, value),
            db_enum=db_enum,
            encoding='utf-8',
            commit=True
        )

    @staticmethod
    @logger
    def delete_monthly_rows(db_enum, schema, table_name, date_column, execution_date):
        ym = str(execution_date.strftime('%Y%m'))

        BaseETL.execute_command(
            command="delete from {}.{} where {} = {}".format(schema, table_name, date_column, ym),
            db_enum=db_enum,
            encoding='utf-8',
            commit=True
        )

    @staticmethod
    @logger
    def extract_query_from_ebdb_to_ods(s3_bucket, schema, table_name, date_column, execution_date):
        file_path = '{}/ebdb/affiliates/{}.sql'.format(SOURCE_QUERIES_DIR, table_name)
        query = BaseETL.get_query_from_file_name(file_name=file_path)

        # delete old records
        AffiliateETL.delete_daily_rows(db_enum=EnumDB.BI_ODS, schema=schema, table_name=table_name,
                                       date_column=date_column, value=str(execution_date))

        logger.info(
            'm=extract_query_from_ebdb_to_ods, file_name={}, schema={}, table={}, msg=loading file query to dw')

        utils.extract_query_dim_from_ebdb_to_ods(
            dim_name=table_name,
            bucket=s3_bucket,
            command=query.format(str_date=str(execution_date)),
            table_name='{}.{}'.format(schema, table_name),
            append=True
        )

    @staticmethod
    @logger
    def append_monthly_data_to_dw_table(file_name, schema, table_name, execution_date, date_column):
        # delete old records
        AffiliateETL.delete_monthly_rows(db_enum=EnumDB.BI_DW, schema=schema, table_name=table_name,
                                         date_column=date_column, execution_date=execution_date)

        logger.info(
            'm=append_monthly_data_to_dw_table, schema={}, table={}, msg=loading file query to dw')

        BaseETL.move_file_query_data_to_db(schema=schema,
                                           file_name=file_name,
                                           table_name=table_name,
                                           append=True,
                                           db_enum_source=EnumDB.BI_DW,
                                           db_enum_destination=EnumDB.BI_DW,
                                           query_params_dict={'execution_date': execution_date})
