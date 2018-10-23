import petl
import time
from datetime import datetime
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl import DATALAKE_QUERIES_DIR, DW_QUERIES_DIR

logger = QuintoAndarLogger('Marketing')

env.set_airflow_var_to_local_env('BI_DW')


class Marketing(object):
    TABLE_PARTITION_DATE = '__PARTITION_DATE__'

    SCHEMA_NAMES = {
        'staging': 'staging',
        'prod': 'marketing'
    }

    def __init__(self, s3_bucket, execution_date, integration=None, account=None):
        self.s3_bucket = s3_bucket
        self.execution_date = execution_date
        self.account = account
        self.partition_date = self.execution_date.strftime('%Y-%m-%d')
        self.athena_client = AthenaClient(self.s3_bucket)
        self.integration = integration
        self.query_path = 'marketing/{integration}/raw_to_clean'.format(integration=self.integration)
        self.database = 'datalake_raw'

    @logger(exclude=['r_cols', 'c_cols'])
    def _move_to_clean(self, table_name, sql_file_name, r_cols, c_cols):
        key = 'clean/marketing/{integration}/{table_name}/acc={acc_partition}/' \
              'dt_created={date_partition}/{file_name}.parquet' \
            .format(
                integration=self.integration,
                table_name=table_name,
                acc_partition=self.account,
                date_partition=self.partition_date,
                file_name=int(time.mktime(datetime.now().timetuple())) * 1000
            )

        query = BaseETL.get_query_from_file_name(
            '{query_base_dir}/{query_path}/{file_name}'.format(
                query_base_dir=DATALAKE_QUERIES_DIR,
                query_path=self.query_path,
                file_name=sql_file_name))

        self.athena_client.add_partition(
            database=self.database,
            table_name=table_name,
            partition="dt='{dt}', acc='{acc}'".format(dt=self.partition_date, acc=self.account)
        )

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query.format(date=self.partition_date, account=self.account),
            raw_columns=r_cols,
            clean_columns=c_cols
        )

    def _load_to_pre_staging(self, clean_table, prod_table, accounts, table_schema):
        clean_schema_name = 'datalake_clean'
        pre_staging_query = "select * from {}.{}".format(clean_schema_name, clean_table)

        empty = self.__is_prod_table_empty(prod_table)
        if empty:
            logger.info(
                'm=load_to_staging, schema={}, table_name={}, msg=table already empty'.format(
                    Marketing.SCHEMA_NAMES['prod'], prod_table))
        else:
            delete_query = "DELETE FROM staging.{table_name} where dt_created = '{date_partition}'"

            self.__update_table_partitions(clean_schema_name, clean_table, accounts)

            BaseETL.execute_command(
                command=delete_query.format(
                    schema=Marketing.SCHEMA_NAMES['staging'],
                    table_name=clean_table,
                    date_partition=self.partition_date),
                db_enum=EnumDB.BI_DW,
                encoding='utf-8',
                commit=True
            )

            pre_staging_query = '{}\nwhere dt_created = \'{}\';'.format(pre_staging_query, self.partition_date)

        df = self.athena_client.execute_query_and_return_dataframe(sql=pre_staging_query)

        logger.info("m=load_to_staging, schema={}, table_name, msg=inserting into staging table".format(
            Marketing.SCHEMA_NAMES['staging'], clean_table))

        df_table = petl.fromdataframe(df=df)

        for column, _type in table_schema.iteritems():
            df_table = petl.convert(df_table, column, _type)

        BaseETL.bulk_insert(
            table=df_table,
            table_name='{}.{}'.format(Marketing.SCHEMA_NAMES['staging'], clean_table),
            db_enum=EnumDB.BI_DW,
            encoding='utf-8',
            append=True,
            commit=True,
        )

    def _load_to_staging(self, dw_table_name):
        staging_query = BaseETL.get_query_from_file_name(
            '{}/staging/marketing/{}.sql'.format(
                DW_QUERIES_DIR,
                dw_table_name))

        empty = self.__is_prod_table_empty(dw_table_name)
        if empty:
            logger.info(
                'm=load_to_staging, schema={}, table_name={}, msg=table already empty'.format(
                    Marketing.SCHEMA_NAMES['prod'], dw_table_name))

            staging_query = staging_query.format(where_clause='')
        else:

            delete_query = "DELETE FROM {schema}.{table_name} where dt_created = '{date_partition}'"

            BaseETL.execute_command(
                command=delete_query.format(
                    schema=Marketing.SCHEMA_NAMES['staging'],
                    table_name=dw_table_name,
                    date_partition=self.partition_date),
                db_enum=EnumDB.BI_DW,
                encoding='utf-8',
                commit=True
            )

            staging_query = staging_query.format(where_clause="dt_created = '{}'".format(self.partition_date))
            # staging_query = '{}\nwhere dt_created = \'{}\';'.format(staging_query, self.partition_date)

        logger.info("m=load_to_staging, schema={}, table_name, msg=inserting into dw".format(
            Marketing.SCHEMA_NAMES['staging'], dw_table_name))

        table_data = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query=staging_query,
            encoding='utf-8',
        )

        BaseETL.bulk_insert(
            table=table_data,
            table_name='{}.{}'.format(Marketing.SCHEMA_NAMES['staging'], dw_table_name),
            db_enum=EnumDB.BI_DW,
            encoding='utf-8',
            append=True,
            commit=True,
        )

    @logger
    def _load_to_prod(self, table_name):
        upsert_query = "SELECT * FROM {}.{}".format(Marketing.SCHEMA_NAMES['staging'], table_name)

        empty = self.__is_prod_table_empty(table_name)
        if empty:
            logger.info(
                'm=load_to_staging, schema={}, table_name={}, msg=table already empty'.format(
                    Marketing.SCHEMA_NAMES['prod'], table_name))
        else:
            self.__delete_old_entries(table_name)
            upsert_query = '{}\n where dt_created = \'{}\';'.format(upsert_query, self.partition_date)

        self.__upsert_into_dw(upsert_query, table_name, Marketing.SCHEMA_NAMES['prod'])

    @logger(exclude='df')
    def __upsert_into_dw(self, upsert_query, table_name, schema):
        logger.info(
            'm=__upsert_into_dw, schema={}, table_name={}, msg=getting data from DW'.format(schema, table_name))
        logger.info(
            'm=__upsert_into_dw, schema={}, table_name={}, \n query={}'.format(schema, table_name, upsert_query))

        table_data = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query=upsert_query,
            encoding='utf-8',
        )

        logger.info(
            '__upsert_into_dw, schema={}, table_name={}, msg=bulk inserting...'.format(schema, table_name))

        BaseETL.bulk_insert(
            table=table_data,
            table_name='{}.{}'.format(schema, table_name),
            db_enum=EnumDB.BI_DW,
            encoding='utf-8',
        )

        logger.info(
            '__upsert_into_dw, schema={}, table_name={}, msg=ready to reading data!'.format(schema, table_name))

    @logger
    def __is_prod_table_empty(self, table_name):
        result = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query="select 1 from marketing.{} limit 1".format(table_name),
            encoding="utf-8"
        )

        return len(result) == 1

    @logger
    def __delete_old_entries(self, table_name):
        delete_query = BaseETL.get_query_from_file_name(
            '{}/marketing/delete_old_entries.sql'.format(DW_QUERIES_DIR)
        )

        BaseETL.execute_command(
            db_enum=EnumDB.BI_DW,
            command=delete_query.format(table_name=table_name).replace(
                Marketing.TABLE_PARTITION_DATE, self.partition_date),
            commit=True,
            encoding='utf-8'
        )

    @logger
    def __update_table_partitions(self, schema_name, table, accounts):
        for acc in accounts:
            self.athena_client.add_partition(
                database=schema_name,
                table_name=table,
                partition="dt_created='{dt}', acc='{acc}'".format(dt=self.partition_date, acc=acc)
            )
