import petl
import os
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR, DW_QUERIES_DIR

logger = QuintoAndarLogger('Marketing')


class Marketing(object):
    TABLE_PARTITION_DATE = '__PARTITION_DATE__'

    SCHEMA_NAMES = {
        'staging': 'staging',
        'prod': 'marketing'
    }

    SK_FIELD_MAP = {
        'dim_google_keyword': 'sk_keyword',
        'dim_google_ad': 'sk_ad',
        'dim_google_campaign': 'sk_campaign',
        'fact_google_daily_cost_attributions': 'sk_keyword || sk_ad',
        'dim_facebook_ad': 'sk_ad',
        'fact_facebook_daily_cost_attributions': 'sk_ad',
        'fact_criteo_daily_cost_attributions': 'sk_criteo_campaign',
        'dim_criteo_campaign': 'sk_criteo_campaign',
        'fact_rtb_daily_cost_attributions': 'sk_sub_campaign',
        'dim_rtb_sub_campaign': 'sk_sub_campaign',
        'dim_trovit_campaign': 'sk_trovit_campaign',
        'fact_trovit_daily_cost_attributions': 'sk_trovit_campaign',
        'dim_mitula_campaign': 'sk_mitula_campaign',
        'fact_mitula_daily_cost_attributions': 'sk_mitula_campaign',
        'dim_twitter_ad': 'sk_ad',
        'dim_twitter_ad_group': 'sk_ad_group',
        'dim_twitter_campaign': 'sk_campaign',
        'fact_twitter_daily_cost_attributions': 'sk_ad',
        'dim_linkedin_campaign_group': 'sk_campaign_group',
        'dim_linkedin_campaign': 'sk_campaign',
        'dim_linkedin_creative': 'sk_creative',
        'fact_linkedin_daily_cost_attributions': 'sk_creative || sk_date'
    }

    def __init__(self, s3_bucket, execution_date, integration=None, account=None):
        self.s3_bucket = s3_bucket
        self.execution_date = execution_date
        self.account = account
        self.partition_date = self.execution_date.strftime('%Y-%m-%d')
        data_acc_aws_access_key_id = os.environ.get('DATA_ACC_AWS_ACCESS_KEY_ID')
        data_acc_aws_secret_access_key = os.environ.get('DATA_ACC_AWS_SECRET_ACCESS_KEY')
        self.athena_client = AthenaClient(self.s3_bucket, data_acc_aws_access_key_id, data_acc_aws_secret_access_key)
        self.integration = integration
        self.raw_query_path = 'marketing/{integration}/raw_to_clean'.format(
            integration=self.integration)
        self.database = 'datalake_raw'

    @logger(exclude=['r_cols', 'c_cols'])
    def _move_to_clean(self, table_name, sql_file_name, r_cols, c_cols=None,
                       validate_data=False):
        key = 'clean/marketing/{integration}/{table_name}/acc={acc_partition}/' \
              'dt_created={date_partition}/{file_name}.parquet' \
            .format(
                integration=self.integration,
                table_name=table_name,
                acc_partition=self.account,
                date_partition=self.partition_date,
                file_name=self.partition_date
            )

        query = BaseETL.get_query_from_file_name(
            '{query_base_dir}/{query_path}/{file_name}'.format(
                query_base_dir=DATALAKE_QUERIES_DIR,
                query_path=self.raw_query_path,
                file_name=sql_file_name))

        self.athena_client.add_partition(
            database=self.database,
            table_name=table_name,
            partition="dt='{dt}', acc='{acc}'".format(dt=self.partition_date,
                                                      acc=self.account)
        )

        if validate_data:
            self._validate_data_with_previous_execution(table_name=table_name)

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query.format(date=self.partition_date, account=self.account),
            raw_columns=r_cols,
            clean_columns=c_cols
        )

        self.athena_client.add_partition(
            database='datalake_clean',
            table_name=table_name,
            partition="dt_created='{dt}', acc='{acc}'".format(dt=self.partition_date,
                                                              acc=self.account)
        )

    @logger(exclude=['table_schema', 'accounts'])
    def _load_to_pre_staging(self, clean_table, prod_table, accounts, table_schema, query=None):
        clean_schema_name = 'datalake_clean'

        BaseETL.truncate_table(
            db_enum=EnumDB.BI_DW,
            table_name=clean_table,
            schema=Marketing.SCHEMA_NAMES['staging']
        )

        if query is None:
            pre_staging_query = "select distinct * from {}.{}".format(clean_schema_name,
                                                                      clean_table)
        else:
            pre_staging_query = query

        empty = self._is_prod_table_empty(prod_table)
        if empty:
            logger.info(
                'm=load_to_staging, schema={}, table_name={}, msg=table already empty'.format(
                    Marketing.SCHEMA_NAMES['prod'], prod_table))

            self.athena_client.execute_raw_query(
                "msck repair table {}.{}".format(clean_schema_name, clean_table))

        else:
            self._update_table_partitions(clean_schema_name, clean_table, accounts)
            pre_staging_query = '{}\nwhere dt_created = \'{}\';'.format(
                pre_staging_query, self.partition_date)

        df = self.athena_client.execute_query_and_return_dataframe(
            sql=pre_staging_query)

        logger.info(
            "m=_load_to_pre_staging, schema={}, table_name={}, msg=inserting into staging table".format(
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

    @logger(exclude=['staging_query'])
    def _load_to_staging(self, dw_table_name, staging_query):

        logger.info(
            "m=load_to_staging, schema={}, table_name={}, msg=truncating table".format(
                Marketing.SCHEMA_NAMES['staging'], dw_table_name))

        BaseETL.truncate_table(
            db_enum=EnumDB.BI_DW,
            table_name=dw_table_name,
            schema=Marketing.SCHEMA_NAMES['staging']
        )

        logger.info(
            "m=load_to_staging, schema={}, table_name={}, msg=inserting into dw".format(
                Marketing.SCHEMA_NAMES['staging'], dw_table_name))

        table_data = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query=staging_query,
            encoding='utf-8',
        )

        if table_data is not None:
            BaseETL.bulk_insert(
                table=table_data,
                table_name='{}.{}'.format(Marketing.SCHEMA_NAMES['staging'], dw_table_name),
                db_enum=EnumDB.BI_DW,
                encoding='utf-8',
                commit=True,
            )

    @logger
    def _load_to_prod(self, table_name):
        table_type = table_name.split("_")[0]

        upsert_query = "SELECT DISTINCT * FROM {}.{}".format(
            Marketing.SCHEMA_NAMES['staging'], table_name)

        empty = self._is_prod_table_empty(table_name)
        if empty:
            logger.info(
                'm=load_to_staging, schema={}, table_name={}, msg=table already empty'.format(
                    Marketing.SCHEMA_NAMES['prod'], table_name))
        else:
            if table_type == 'fact':
                delete_query = BaseETL.get_query_from_file_name(
                    '{}/marketing/delete_fact_old_entries.sql'.format(DW_QUERIES_DIR))

                self._delete_old_entries(table_name=table_name,
                                         delete_query=delete_query)
                upsert_query = "{} \nwhere sk_date = {};".format(upsert_query,
                                                                 self.execution_date.strftime(
                                                                     '%Y%m%d'))
            else:
                delete_query = BaseETL.get_query_from_file_name(
                    '{}/marketing/delete_dim_old_entries.sql'.format(DW_QUERIES_DIR))

                self._delete_old_entries(table_name=table_name,
                                         delete_query=delete_query)
                upsert_query = """
                    SELECT * FROM staging.{dim_table}
                    WHERE {sk_field} not in (
                        SELECT {sk_field} from marketing.{dim_table}
                    )
                """.format(sk_field=Marketing.SK_FIELD_MAP[table_name],
                           dim_table=table_name)

        self._upsert_into_dw(upsert_query, table_name, Marketing.SCHEMA_NAMES['prod'])

    @logger(exclude='df')
    def _upsert_into_dw(self, upsert_query, table_name, schema):
        logger.info(
            'm=__upsert_into_dw, schema={}, table_name={}, msg=getting data from DW, query={}'.format(
                schema,
                table_name,
                upsert_query))

        table_data = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query=upsert_query,
            encoding='utf-8',
        )

        logger.info(
            '__upsert_into_dw, schema={}, table_name={}, msg=bulk inserting...'.format(
                schema, table_name))

        BaseETL.bulk_insert(
            table=table_data,
            table_name='{}.{}'.format(schema, table_name),
            db_enum=EnumDB.BI_DW,
            encoding='utf-8',
            append=True,
            commit=True
        )

        logger.info(
            '__upsert_into_dw, schema={}, table_name={}, msg=ready to reading data!'.format(
                schema, table_name))

    @staticmethod
    @logger
    def _is_staging_table_empty(table_name):
        result = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query="select 1 from staging.{} limit 1".format(table_name),
            encoding="utf-8"
        )

        return len(result) == 1

    @logger
    def _is_prod_table_empty(self, table_name):
        result = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query="select 1 from marketing.{} limit 1".format(table_name),
            encoding="utf-8"
        )

        return len(result) == 1

    @logger(exclude='delete_query')
    def _delete_old_entries(self, table_name, delete_query):
        BaseETL.execute_command(
            db_enum=EnumDB.BI_DW,
            command=delete_query.format(
                table_name=table_name,
                sk_field=Marketing.SK_FIELD_MAP[table_name]
            ).replace(Marketing.TABLE_PARTITION_DATE,
                      self.execution_date.strftime('%Y%m%d')),
            commit=True,
            encoding='utf-8'
        )

    @logger
    def _update_table_partitions(self, schema_name, table, accounts):
        for acc in accounts:
            self.athena_client.add_partition(
                database=schema_name,
                table_name=table,
                partition="dt_created='{dt}', acc='{acc}'".format(
                    dt=self.partition_date, acc=acc)
            )

    @logger
    def _validate_data_with_previous_execution(self, table_name):
        file_query = (
            '{query_base_dir}/{query_path}/row_count_test.sql'.format(
                query_base_dir=DATALAKE_QUERIES_DIR,
                query_path=self.raw_query_path))

        df = self.athena_client.execute_file_query_and_return_dataframe(
            filename=file_query,
            query_params={'table_name': table_name,
                          'date': self.partition_date,
                          'account': self.account})

        try:
            # Due to a issue in comparing numpy.bool_ type we compare it using pandas
            df = df.eq(True)
            result = df.iloc[0][0]
        except Exception as e:
            raise ValueError(
                'm=_validate_data_with_previous_execution, file_query_path={0}, date={1}, account={2}, error={3}, '
                'msg=Validation query did not return any expected result'.format(
                    file_query, self.partition_date,
                    self.account, str(e.message)))
        if not result:
            raise ValueError(
                'm=_validate_data_with_previous_execution, file_query_path={0}, date={1}, account={2}, '
                'msg=Validation not successful'.format(file_query, self.partition_date,
                                                       self.account))

        logger.info('m=_validate_data_with_previous_execution, date={0}, account={1}, '
                    'msg=Validation successful'.format(self.partition_date,
                                                       self.account))
