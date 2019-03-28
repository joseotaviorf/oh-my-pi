import json
from collections import OrderedDict
from datetime import timedelta
from gzip import GzipFile
from io import BytesIO

import petl
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.google.google_sheets import GoogleSheetsClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl import DW_QUERIES_DIR
from bietlejuice.jobs.etl.crm.tasks.tasks import UnidecodeHandler
from bietlejuice.jobs.etl.marketing.marketing import Marketing

logger = QuintoAndarLogger('ClassifiedsCosts')


class ClassifiedsCosts(Marketing):
    TABLE_PARTITION_DATE = '__PARTITION_DATE__'
    TABLE_PARTITION_ACCOUNT = '__PARTITION_ACCOUNT__'

    COLUMN_TYPE_MAP = {
        'marketing_classifieds_costs': {
            'source': str,
            'cost': long
        }
    }

    def __init__(self, s3_bucket, execution_date, account=None, auth=None):
        self.auth = auth
        self.google_api_scope = 'https://www.googleapis.com/auth/spreadsheets.readonly'
        # add the day that was subtracted before in the marketing_subdag
        execution_date = execution_date + timedelta(1)
        self.sheet_name = execution_date.strftime('%Y-%m-%d')
        super(ClassifiedsCosts, self).__init__(s3_bucket, execution_date, 'classifieds_costs', account)

    @logger(exclude='sheet_id')
    def _get_google_sheets_data(self, sheet_id):
        g_sheets = GoogleSheetsClient(
            self.auth['sheet_credentials'],
            self.google_api_scope
        )

        return g_sheets.get_dataframe_from_sheet(self.sheet_name, str(sheet_id))

    @logger(exclude='df')
    def _save_to_s3(self, df):
        if df is None or len(df) == 0:
            logger.info('m=_save_to_s3, msg=no results')
            return

        # Delete the useless "medium" column from the dataframe
        df = df.drop("medium", axis=1)
        json_list = df.to_dict(orient='records')
        logger.info('m=_save_to_s3, msg=gzipping json')
        gz_body = BytesIO()
        for _json in json_list:
            with GzipFile(fileobj=gz_body, mode='w') as fp:
                fp.write((json.dumps(_json, ensure_ascii=False, cls=UnidecodeHandler)).encode('utf-8'))
                fp.write('\n')

        file_suffix = 'raw/marketing/classifieds_costs/acc=default/dt={}/data.gz'.format(
            self.execution_date.strftime('%Y-%m-%d'))
        BaseETL.obj_to_s3(
            obj_io=gz_body,
            bucket=self.s3_bucket,
            file_path=file_suffix
        )

        # clear obj allocation
        # only flushing does not clear the buffer
        gz_body.seek(0)
        gz_body.flush()

        logger.info('m=__save_to_s3, msg= rows saved')

    @logger
    def move_classifieds_costs_to_raw(self):
        df_gsheets = self._get_google_sheets_data(self.auth['sheet_id'])

        self.athena_client.add_partition(
            database='datalake_raw',
            table_name='marketing_classifieds_costs',
            partition="dt='{dt}', acc='{acc}'".format(dt=self.partition_date, acc=self.account)
        )

        self._save_to_s3(df_gsheets)

    @logger
    def move_classifieds_costs_to_clean(self):
        r_cols = OrderedDict([
            ('source', str),
            ('cost', str)
        ])

        c_cols = OrderedDict([
            ('source', str),
            ('cost', str)
        ])

        self._move_to_clean(
            table_name='marketing_classifieds_costs',
            sql_file_name='classifieds_costs.sql',
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger
    def load_to_staging(self, dw_table_name):
        query, column_types = self.__load_table(dw_table_name)
        # this line will pass the attributes to the called query and format correctly
        query = query.format(date=self.partition_date, account='default')
        logger.info("m=load_to_staging, query={}".format(query))
        self._load_to_staging(dw_table_name, query, column_types)

    @logger
    def __load_table(self, table_name):
        table_type = table_name.split('_')[0]
        return getattr(self, '_load_{}_to_staging'.format(table_type))(table_name)

    # this is the method that returns the dim query
    def _load_dim_to_staging(self, table_name):
        dim_query = BaseETL.get_query_from_file_name(
            '{}/marketing/{}/clean_to_staging/{}.sql'.format(
                DATALAKE_QUERIES_DIR,
                'classifieds_costs',
                table_name))

        return dim_query, [{'column': 'sk_classified', 'type': int}]

    @logger
    def _load_fact_to_staging(self, table_name):
        int_date = int(self.execution_date.strftime("%Y%m%d"))

        fact_query = BaseETL.get_query_from_file_name(
            '{}/marketing/{}/clean_to_staging/{}.sql'.format(
                DATALAKE_QUERIES_DIR,
                'classifieds_costs',
                table_name))

        empty = self._is_prod_table_empty(table_name)
        if empty:
            logger.info(
                'm=load_to_staging, schema={}, table_name={}, msg=table already empty'.format(
                    Marketing.SCHEMA_NAMES['prod'], table_name))
        else:
            delete_query = "DELETE FROM {schema}.{table_name} where sk_cost_date = {date_partition}"

            BaseETL.execute_command(
                command=delete_query.format(
                    schema=Marketing.SCHEMA_NAMES['staging'],
                    table_name=table_name,
                    date_partition=int_date),
                db_enum=EnumDB.BI_DW,
                encoding='utf-8',
                commit=True
            )

            BaseETL.execute_command(
                command=delete_query.format(
                    schema=Marketing.SCHEMA_NAMES['prod'],
                    table_name=table_name,
                    date_partition=int_date),
                db_enum=EnumDB.BI_DW,
                encoding='utf-8',
                commit=True
            )

        return fact_query, [{'column': 'sk_classified', 'type': int}, {'column': 'sk_cost_date', 'type': int}]

    @logger(exclude=['staging_query', 'column_types'])
    def _load_to_staging(self, dw_table_name, staging_query, column_types=None):

        logger.info("m=load_to_staging, schema={}, table_name={}, msg=truncating table".format(
            Marketing.SCHEMA_NAMES['staging'], dw_table_name))

        df = self.athena_client.execute_query_and_return_dataframe(sql=staging_query)

        logger.info("m=_load_to_staging, schema={}, table_name={}, msg=inserting into staging table".format(
            Marketing.SCHEMA_NAMES['staging'], dw_table_name))

        df_table = petl.fromdataframe(df=df)

        for ct in column_types:
            df_table = petl.convert(df_table, ct['column'], ct['type'])

        BaseETL.bulk_insert(
            table=df_table,
            table_name='{}.{}'.format(Marketing.SCHEMA_NAMES['staging'], dw_table_name),
            db_enum=EnumDB.BI_DW,
            encoding='utf-8',
            append=False,
            commit=True,
        )

    @logger
    def load_to_prod(self, table_name):
        self._load_to_prod(table_name)

    @logger
    def _load_to_prod(self, table_name):
        table_type = table_name.split("_")[0]

        upsert_query = "SELECT DISTINCT * FROM {}.{}".format(Marketing.SCHEMA_NAMES['staging'], table_name)

        empty = self._is_prod_table_empty(table_name)
        if empty:
            logger.info(
                'm=load_to_staging, schema={}, table_name={}, msg=table already empty'.format(
                    Marketing.SCHEMA_NAMES['prod'], table_name))
        else:
            if table_type == 'fact':
                delete_query = BaseETL.get_query_from_file_name(
                    '{}/marketing/classifieds_costs/delete_fact_old_entries.sql'.format(DW_QUERIES_DIR))

                self.__delete_old_entries(table_name=table_name, delete_query=delete_query)
                upsert_query = "{} \nwhere sk_cost_date = {};".format(upsert_query,
                                                                      self.execution_date.strftime('%Y%m%d'))
            else:
                delete_query = BaseETL.get_query_from_file_name(
                    '{}/marketing/classifieds_costs/delete_dim_old_entries.sql'.format(DW_QUERIES_DIR))

                self.__delete_old_entries(table_name=table_name, delete_query=delete_query)
                upsert_query = """
                        SELECT * FROM staging.{dim_table}
                        WHERE {sk_field} not in (
                            SELECT {sk_field} from marketing.{dim_table}
                        )
                    """.format(sk_field=Marketing.SK_FIELD_MAP[table_name], dim_table=table_name)

        self._upsert_into_dw(upsert_query, table_name, Marketing.SCHEMA_NAMES['prod'])

    @logger
    def __delete_old_entries(self, table_name, delete_query):
        BaseETL.execute_command(
            db_enum=EnumDB.BI_DW,
            command=delete_query.replace(Marketing.TABLE_PARTITION_DATE, self.execution_date.strftime('%Y%d%m')),
            commit=True,
            encoding='utf-8'
        )
