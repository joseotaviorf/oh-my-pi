import os
import sys
from io import BytesIO

import boto3
import petl
import pandas as pd
from jobs.base.base_etl import BaseETL, EnumDb
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger

args = sys.argv
bucket_datalake = os.environ['bi-datalake-s3-bucket']
athena_db = 'datalake_raw'
schema_name = 'ebdb'


class EBDBDatalake(object):
    def __init__(self):
        self.s3_client = boto3.resource('s3')

    @logger
    def move_to_datalake(self, table_name):
        now = BaseETL.now()
        db = EnumDb.QuintoAndar_ebdb

        _logger.info('m=move_to_datalake, msg=start query: {}'.format(now))

        # get data from table
        table = BaseETL.from_db_table(
            db_enum=db,
            table_name=table_name,
            generator=True
        ).addfield('dt_timestamp', now)

        _logger.info('m=move_to_datalake, msg=to ODS: {}'.format(now))

        table = BaseETL.decode_table(table, 'LATIN-1')  # decode table from LATIN-1
        table = petl.convertall(table, unicode)  # convert all fields to unicode

        # get all columns declared as BIT because we have a bug converting BIT columns on mysql
        bit_columns = petl.select(BaseETL.get_columns_schema(EnumDb.QuintoAndar_ebdb, table_name, schema_name, False),
                                  lambda rec: rec.DATA_TYPE == 'bit')
        table = petl.convert(table, tuple(bit_columns['COLUMN_NAME']), {u'\x00': u'0', u'\x01': u'1'})

        # save table into datalake
        file_path = 'raw/{1}/{2}/{2}.csv'.format(bucket_datalake, schema_name, table_name)
        df_table = petl.todataframe(table)

        # replace Nan for SQL Null
        df_table = df_table.astype(object).where(pd.notnull(df_table), None)

        csv_buffer = BytesIO()
        df_table.to_csv(csv_buffer, index=False, sep=',', encoding='utf-8', header=False)

        self.s3_client.Object(bucket_datalake, file_path).put(Body=csv_buffer.getvalue())

        _logger.info('m=move_to_datalake, msg={} moved to Datalake!'.format(table_name))

    @logger
    def get_type_conversion_dict(self):
        conversions_table = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query="""
                select 
                    distinct	DATA_TYPE,
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

    def create_external_table(self, table_name, conv):
        columns = BaseETL.get_columns_schema(EnumDb.QuintoAndar_ebdb, table_name, schema_name)
        c = AthenaClient(bucket_datalake)
        c.execute_query_and_wait_for_results(
            'drop table if exists {}.{}_{};'.format(athena_db, schema_name, table_name))

        command = 'create external table {}.{}_{} (\n'.format(athena_db, schema_name, table_name)
        for column, original_type in columns:
            command += '\t{} {},\n'.format(column, conv[original_type])
        command = command[:-2]  # remove last comma
        command += """) row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
                         with serdeproperties (
                           'separatorChar' = ',',
                           'quoteChar' = '\"'
                         )
                        stored as textfile
                        location 's3://{}/raw/{}/{}/'""".format(bucket_datalake, schema_name, table_name)

        c.execute_query_and_wait_for_results(command)

    @logger
    def get_table_names(self, skip_header=True):
        sql_tables = """
        select TABLE_NAME
        from information_schema.TABLES
        where TABLE_SCHEMA = '{}'
        and TABLE_TYPE = 'BASE TABLE'    
    """.format(schema_name)
        table_names = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query=sql_tables
        )
        if skip_header:
            table_names.pop(0)  # remove header
        return table_names


if __name__ == '__main__':
    ebdb_datalake = EBDBDatalake()
    table_names = ebdb_datalake.get_table_names()

    if args[1] == 'move':
        for table_name in table_names:
            ebdb_datalake.move_to_datalake(table_name[0])
    elif args[1] == 'create_tables':
        conversions = ebdb_datalake.get_type_conversion_dict()
        for table_name in table_names:
            ebdb_datalake.create_external_table(table_name[0], conversions)
    else:
        _logger.info('m=__main__, msg=arg \'{}\' not recognized'.format(args[1]))
