import json
from collections import OrderedDict
from gzip import GzipFile
from io import BytesIO

import petl
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.google.google_sheets import GoogleSheetsClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.crm.tasks.tasks import UnidecodeHandler
from bietlejuice.jobs.etl.marketing.marketing import Marketing

logger = QuintoAndarLogger('ClassifiedsCosts')


class ClassifiedsCosts(Marketing):
    INTEGRATION = 'classifieds_costs'

    def __init__(self, s3_bucket, execution_date, account=None, auth=None,
                 extra_configs=None):
        month_first_day = self._force_month_first_day(execution_date)
        super(ClassifiedsCosts, self).__init__(s3_bucket, month_first_day,
                                               self.INTEGRATION, account)
        self.auth = auth
        self.sheet_name = self.partition_date
        self.funnel_side = self._extract_extra_config(extra_configs, 'side')
        self.sheet_id = self._extract_extra_config(extra_configs, 'sheet_id')

    @staticmethod
    def _force_month_first_day(execution_date):
        return execution_date.replace(day=1)

    @logger
    def move_classifieds_costs_to_raw(self):
        df_gsheets = self._get_google_sheets_data()
        self._save_to_s3(df_gsheets)

    @staticmethod
    def _extract_extra_config(extra_configs, config):
        value = None
        if extra_configs and config in extra_configs and \
                extra_configs[config] is not None:
            value = extra_configs[config]

        return value

    def _get_extra_config(self, config):
        config_value = getattr(self, config)
        if not config_value:
            raise ValueError('m=_get_funnel_side msg={} is empty'.format(config))
        return config_value

    @logger
    def _get_google_sheets_data(self):
        g_sheets = GoogleSheetsClient(
            self.auth['GSA_CREDENTIALS'],
            self.auth['GOOGLE_API_SCOPE']
        )
        return g_sheets.get_dataframe_from_sheet(self.sheet_name, str(
            self._get_extra_config('sheet_id')))

    @logger(exclude='df')
    def _save_to_s3(self, raw_data):
        if raw_data is None or len(raw_data) == 0:
            logger.info('m=_save_to_s3, msg=There\'s no data to be saved.')
            return

        raw_data = raw_data.applymap(str)
        raw_data_list = raw_data.to_dict(orient='records')

        logger.info('m=_save_to_s3, msg=Gzipping raw data')
        gz_body = BytesIO()
        for _dict in raw_data_list:
            with GzipFile(fileobj=gz_body, mode='w') as fp:
                fp.write((json.dumps(_dict, ensure_ascii=False,
                                     cls=UnidecodeHandler)).encode('utf-8'))
                fp.write('\n')

        funnel_side = self._get_extra_config('funnel_side')
        s3_file_path = 'raw/marketing/classifieds_costs/{}/acc=default/dt={}/data.gz'. \
            format(funnel_side, self.execution_date.strftime('%Y-%m-%d'))

        logger.info('m=_save_to_s3, dest={}, msg=Saving {} classifieds data into s3 '
                    'bucket'.format(s3_file_path, funnel_side))

        BaseETL.obj_to_s3(
            obj_io=gz_body,
            bucket=self.s3_bucket,
            file_path=s3_file_path
        )

        gz_body.seek(0)
        gz_body.flush()

        logger.info('m=_save_to_s3, msg=Saved with success!')

    @logger
    def move_classifieds_demand_costs_to_clean(self):
        c_cols = OrderedDict([
            ('medium', str),
            ('source', str),
            ('cost', str)
        ])

        self._move_to_clean(
            table_name='marketing_demand_classifieds_costs',
            sql_file_name='classifieds_demand_costs.sql',
            r_cols=c_cols,
            c_cols=c_cols
        )

    @logger
    def move_classifieds_supply_costs_to_clean(self):
        c_cols = OrderedDict([
            ('medium', str),
            ('source', str),
            ('cost', str)
        ])

        self._move_to_clean(
            table_name='marketing_supply_classifieds_costs',
            sql_file_name='classifieds_supply_costs.sql',
            r_cols=c_cols,
            c_cols=c_cols
        )

    @logger
    def load_to_staging(self, dw_table_name):
        query = self._get_staging_table_query(dw_table_name)
        query = query.format(date=self.partition_date)  # todo remove add das queries
        logger.info("m=load_to_staging, query={}".format(query))

        self._load_to_staging(dw_table_name, query)

    @logger
    def _get_staging_table_query(self, table_name):
        """
        Gets the table query to select data from clean tables on Athena
        If it's a fact table and staging is not empty,
        then it'll load only the data of the execution day
        """
        full_load_query = BaseETL.get_query_from_file_name(
            '{}/marketing/{}/clean_to_staging/{}.sql'.format(
                DATALAKE_QUERIES_DIR, self.INTEGRATION, table_name))

        if self._table_type(table_name) == 'fact' and not self._is_staging_table_empty(
                table_name):
            sk_date = int(self.execution_date.strftime('%Y%m%d'))
            self._delete_fact_rows(table_name, sk_date)

            daily_load_query = "{full_load_query} \nWHERE sk_date BETWEEN " \
                               "{date_start_month} AND {date_end_month};" \
                .format(full_load_query=full_load_query,
                        date_start_month=sk_date,
                        date_end_month=sk_date + 30)
            return daily_load_query

        return full_load_query

    @staticmethod
    @logger
    def _table_type(table_name):
        return table_name.split('_')[0]

    @logger
    def _delete_fact_rows(self, table_name,
                          sk_date):
        # Since we load costs for entire month of execution_date on this dag,
        # we should delete entire month costs here
        delete_query = "DELETE FROM staging.{table_name} " \
                       "WHERE sk_date BETWEEN " \
                       "{date_start_month} AND {date_end_month}" \
            .format(table_name=table_name, date_start_month=sk_date,
                    date_end_month=sk_date + 30)
        logger.info("m=_delete_fact_rows, query={}".format(delete_query))

        BaseETL.execute_command(
            db_enum=EnumDB.BI_DW,
            command=delete_query,
            commit=True,
            encoding='utf-8'
        )

    @logger(exclude="staging_query")
    def _load_to_staging(self, dw_table_name, staging_query, column_types=None):

        logger.info("m=_load_to_staging, schema={}, table_name={}, "
                    "msg=Inserting into dw".format(Marketing.SCHEMA_NAMES['staging'],
                                                   dw_table_name))

        pd_df = self.athena_client.execute_query_and_return_dataframe(sql=staging_query)

        logger.info(
            "m=_load_to_staging, schema={}, table_name={}, msg=Inserting into staging "
            "table".format(
                Marketing.SCHEMA_NAMES['staging'], dw_table_name))

        df_table = petl.fromdataframe(df=pd_df)

        BaseETL.bulk_insert(
            table=df_table,
            table_name='{}.{}'.format(Marketing.SCHEMA_NAMES['staging'], dw_table_name),
            db_enum=EnumDB.BI_DW,
            encoding='utf-8',
            append=False if self._table_type(dw_table_name) == 'dim' else True,
            commit=True
        )

    @logger
    def load_to_prod(self, table_name):
        self._load_to_prod(table_name)
