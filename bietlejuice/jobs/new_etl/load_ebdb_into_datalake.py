from io import BytesIO

import boto3
import pandas as pd
import petl
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger

from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb


class EBDBDatalake(object):
    SCHEMA_NAME = 'ebdb'
    RAW_DDL_SUFFIX = """
                ) row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
                with serdeproperties (
                    'separatorChar' = ',',
                    'quoteChar' = '\"'
                )
                tblproperties (
                    'skip.header.line.count' = '1'
                )
                location 's3://{}/raw/{}/{}/'
            """

    CLEAN_DDL_SUFFIX = """
        ) stored as parquet
        location 's3://{}/clean/{}/{}/'
    """

    def __init__(self, bucket_datalake, incremental_date=None):
        self.bucket_datalake = bucket_datalake
        self.s3_client = boto3.resource('s3')
        self.athena_client = AthenaClient(bucket_datalake)
        self.incremental_date = incremental_date

    @logger
    def move_to_datalake(self, table_name):
        now = BaseETL.now()
        db = EnumDb.QuintoAndar_ebdb

        _logger.info('m=move_to_datalake, msg=start query: {}'.format(now))

        schema = BaseETL.get_columns_schema(EnumDb.QuintoAndar_ebdb, table_name, EBDBDatalake.SCHEMA_NAME, False)
        schema = petl.todataframe(schema)

        columns = []
        for _, row in schema.iterrows():
            if row.DATA_TYPE == 'bit':
                columns.append("""cast(t.`{column}` as unsigned) as `{column}`""".format(column=row.COLUMN_NAME))
            elif row.DATA_TYPE == 'longblob':
                columns.append("""AsText(t.`{column}`) as `{column}`""".format(column=row.COLUMN_NAME))
            else:
                columns.append("""t.`{}`""".format(row.COLUMN_NAME))

        table, file_path_suffix = self.__get_data_from_table(
            db=db,
            table_name=table_name,
            columns=columns
        )

        self.__save_table_into_datalake(
            table=table,
            table_name=table_name,
            file_path_suffix=file_path_suffix
        )

        _logger.info('m=move_to_datalake, msg={} moved to Datalake!'.format(table_name))

    @logger
    def __get_data_from_table(self, db, table_name, columns):
        if '_AUD' in table_name:
            _date = self.incremental_date.strftime('%Y-%m-%d')
            query = """
                        select distinct {}
                        from {} t
                        join UsuarioRevisionEntity ure
                            on t.REV = ure.id
                        where date(from_unixtime(ure.`timestamp` / 1000)) = date('{}')
            """.format(', '.join(columns), table_name, _date)
            file_path_suffix = '_{}'.format(_date)
        else:
            query = 'select {} from {} t'.format(', '.join(columns), table_name)
            file_path_suffix = ''

        table = BaseETL.from_db_query(db, query)
        table = BaseETL.decode_table(table, 'LATIN-1')  # decode table from LATIN-1
        return petl.convertall(table, unicode), file_path_suffix  # convert all fields to unicode

    @logger(exclude='table')
    def __save_table_into_datalake(self, table, table_name, file_path_suffix):
        file_path = 'raw/{1}/{2}/{2}{3}.csv'.format(self.bucket_datalake, EBDBDatalake.SCHEMA_NAME, table_name,
                                                    file_path_suffix)
        df_table = petl.todataframe(table)

        # replace Nan for SQL Null
        df_table.replace(['None'], [None], inplace=True)
        df_table = df_table.astype(object).where(pd.notnull(df_table), None)

        # replace '\n' and '\r for space
        df_table.replace('\n', ' ', regex=True, inplace=True)
        df_table.replace('\r', ' ', regex=True, inplace=True)

        csv_buffer = BytesIO()
        df_table.to_csv(csv_buffer, index=False, sep=',', encoding='utf-8', header=False)

        self.s3_client.Object(self.bucket_datalake, file_path).put(Body=csv_buffer.getvalue())

    def transform_tables_to_clean(self, table_infos):
        _logger.info('m=transform_tables_to_clean, msg=init')

        for table_info in table_infos:
            df = self.athena_client.execute_query_and_return_dataframe(
                'select * from datalake_raw.ebdb_{}'.format(table_info['original_name']))

            self.athena_client.create_parquet_from_df(
                key='clean/ebdb/{0}/{0}.parq'.format(table_info['new_name']),
                df=df
            )

            self.create_external_table(
                table_info['new_name'],
                EBDBDatalake.CLEAN_DDL_SUFFIX,
                table_info['original_name'],
                'datalake_clean'
            )

    @logger
    def get_type_conversion_dict(self):
        conversions_table = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query="""
                select
                    distinct DATA_TYPE,
                    case
                        when DATA_TYPE in ('bigint', 'smallint', 'double', 'timestamp', 'int') then DATA_TYPE
                        when DATA_TYPE in ('datetime', 'time') then 'timestamp'
                        when DATA_TYPE in ('bit', 'tinyint') then 'smallint'
                        when DATA_TYPE in ('float', 'decimal', 'numeric') then 'double'
                        else 'string'
                    end as ret
                from information_schema.COLUMNS
            """
        )
        conversions_table.pop(0)
        conversions = {}
        for k, v in conversions_table:
            conversions[k] = v
        return conversions

    def create_external_table(self, table_name, ddl_suffix, original_table_name=None, athena_db='datalake_raw'):
        if not original_table_name:
            original_table_name = table_name

        columns = BaseETL.get_columns_schema(EnumDb.QuintoAndar_ebdb, original_table_name, EBDBDatalake.SCHEMA_NAME)
        self.athena_client.execute_query_and_wait_for_results(
            'drop table if exists {}.{}_{};'.format(athena_db, EBDBDatalake.SCHEMA_NAME, table_name))

        command = 'create external table {}.{}_{} (\n'.format(athena_db, EBDBDatalake.SCHEMA_NAME, table_name)
        for column, original_type in columns:
            command += '\t{} string,\n'.format(column)
        command = command[:-2]  # remove last comma
        command += ddl_suffix.format(self.bucket_datalake, EBDBDatalake.SCHEMA_NAME, table_name)

        self.athena_client.execute_query_and_wait_for_results(command)

    def create_raw_external_tables(self, table_names):
        for table_name in table_names:
            self.create_external_table(table_name[0], EBDBDatalake.RAW_DDL_SUFFIX)

    @logger
    def get_table_names(self, skip_header=True):
        sql_tables = """
                        select TABLE_NAME
                        from information_schema.TABLES
                        where TABLE_SCHEMA = '{}'
                            and (TABLE_TYPE = 'BASE TABLE'
                                    or TABLE_NAME = 'MapRegiao'
                            )
                    """.format(EBDBDatalake.SCHEMA_NAME)
        table_names = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query=sql_tables
        )

        if skip_header:
            table_names.pop(0)  # remove header

        return table_names
