from datetime import datetime

import boto3
from __init__ import QUERIES_DIR
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb
from qa_python_utils.default_logger import _logger


class Agent_Region(object):
    def __init__(self):
        self.schema_name = ''
        self.bucket_datalake = '5a-datalake'
        self.s3_client = boto3.resource('s3')

    def __format_query_filename(self, filename):
        return '{}/{}.sql'.format(QUERIES_DIR, filename)

    def get_agent_region(self, f_name, dt=None):
        filename = self.__format_query_filename(f_name)
        with open(filename) as f:
            raw_query = f.read()

        if dt is not None:
            raw_query = raw_query.format(str(dt))

        agent_region_data = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query=raw_query
        )

        return agent_region_data

    def clean_agent_region(self, schema, table):
        filename = "TRUNCATE TABLE {}.{}"
        raw_query = filename.format(schema, table)

        BaseETL.execute_command(
            db_enum=EnumDb.BI_ODS,
            encoding='UTF8',  # conn=conn,
            command=raw_query,
            commit=True
        )

    def get_agent_region_daily(self):
        filename = self.__format_query_filename('etl_agent_region')
        with open(filename) as f:
            raw_query = f.read()

        agent_region_data = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query=raw_query
        )

        return agent_region_data

    def move_data_to_ods(self, data, table_name):
        _logger.info("To ODS: {}".format(datetime.now()))
        table = BaseETL.decode_table(data, 'LATIN-1')
        BaseETL.bulk_insert(
            table=table,
            table_name=table_name,
            db_enum=EnumDb.BI_ODS,
            encoding='UTF8',
            append=False,
            commit=True,
            bucket_name='{}/raw/ods/{}'.format(self.bucket_datalake, table_name))

    def process_new_rows(self, data):
        print('oi')

    # def move_to_datalake(self, table_name):
    #     now = BaseETL.now()
    #     db = EnumDb.QuintoAndar_ebdb
    #
    #     _logger.info('m=move_to_datalake, msg=start query: {}'.format(now))
    #
    #     # get data from table
    #     table = BaseETL.from_db_table(
    #         db_enum=db,
    #         table_name=table_name,
    #         generator=True
    #     ).addfield('dt_timestamp', now)
    #
    #     _logger.info('m=move_to_datalake, msg=to ODS: {}'.format(now))
    #
    #     table = BaseETL.decode_table(table, 'LATIN-1')  # decode table from LATIN-1
    #     table = petl.convertall(table, unicode)  # convert all fields to unicode
    #
    #     # get all columns declared as BIT because we have a bug converting BIT columns on mysql
    #     bit_columns = petl.select(
    #         BaseETL.get_columns_schema(
    #             EnumDb.QuintoAndar_ebdb,
    #             table_name,
    #             self.schema_name,
    #             False),
    #         lambda rec: rec.DATA_TYPE == 'bit')
    #     table = petl.convert(table, tuple(bit_columns['COLUMN_NAME']), {u'\x00': u'0', u'\x01': u'1'})
    #
    #     # save table into datalake
    #     file_path = 'raw/{1}/{2}/{2}.csv'.format(self.bucket_datalake, self.schema_name, table_name)
    #     df_table = petl.todataframe(table)
    #
    #     # replace Nan for SQL Null
    #     df_table.replace(['None'], [None], inplace=True)
    #     df_table = df_table.astype(object).where(pd.notnull(df_table), None)
    #
    #     # replace '\n' and '\r for space
    #     df_table.replace('\n', ' ', regex=True, inplace=True)
    #     df_table.replace('\r', ' ', regex=True, inplace=True)
    #
    #     csv_buffer = BytesIO()
    #     df_table.to_csv(csv_buffer, index=False, sep=',', encoding='utf-8', header=False)
    #
    #     self.s3_client.Object(self.bucket_datalake, file_path).put(Body=csv_buffer.getvalue())
    #
    #     _logger.info('m=move_to_datalake, msg={} moved to Datalake!'.format(table_name))
    #
    # def transform_tables_to_clean(self, table_infos, ddl_suffix):
    #     _logger.info('m=transform_tables_to_clean, msg=init')
    #
    #     for table_info in table_infos:
    #         df = self.athena_client.execute_query_and_return_dataframe("""
    #               select * from datalake_raw.ebdb_{}""".format(table_info['original_name']))
    #
    #         self.athena_client.create_parquet_from_df(
    #             key='clean/ebdb/{0}/{0}.parq'.format(table_info['new_name']),
    #             df=df
    #         )
    #
    #         self.create_external_table(table_info['new_name'], ddl_suffix, table_info['original_name'],
    #                                    'datalake_clean')
    #
    # @logger
    # def get_type_conversion_dict(self):
    #     conversions_table = BaseETL.from_db_query(
    #         db_enum=EnumDb.QuintoAndar_ebdb,
    #         query="""
    #             select
    #                 distinct	DATA_TYPE,
    #                 case
    #                     when DATA_TYPE in ('bigint', 'smallint', 'double', 'timestamp', 'int') then DATA_TYPE
    #                     when DATA_TYPE in ('datetime', 'time') then 'timestamp'
    #                     when DATA_TYPE in ('bit', 'tinyint') then 'smallint'
    #                     when DATA_TYPE in ('float', 'decimal', 'numeric') then 'double'
    #                     else 'string'
    #                 end as ret
    #             from information_schema.COLUMNS
    #         """
    #     )
    #     conversions_table.pop(0)
    #     conversions = {}
    #     for k, v in conversions_table:
    #         conversions[k] = v
    #     return conversions
    #
    # def create_external_table(self, table_name, ddl_suffix, original_table_name=None, athena_db='datalake_raw'):
    #     if not original_table_name:
    #         original_table_name = table_name
    #
    #     columns = BaseETL.get_columns_schema(EnumDb.QuintoAndar_ebdb, original_table_name, self.schema_name)
    #     self.athena_client.execute_query_and_wait_for_results(
    #         'drop table if exists {}.{}_{};'.format(athena_db, self.schema_name, table_name))
    #
    #     command = 'create external table {}.{}_{} (\n'.format(athena_db, self.schema_name, table_name)
    #     for column, original_type in columns:
    #         command += '\t{} string,\n'.format(column)
    #         # command += '\t{} {},\n'.format(column, conv[original_type])
    #     command = command[:-2]  # remove last comma
    #     command += ddl_suffix.format(self.bucket_datalake, self.schema_name, table_name)
    #
    #     self.athena_client.execute_query_and_wait_for_results(command)
