import boto3
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.new_etl import DW_QUERIES_DIR
from qa_python_utils.default_logger import logger


class Bridge(object):
    def __init__(self, bucket_name):
        self.schema_name = ''
        self.bucket_datalake = bucket_name
        self.s3_client = boto3.resource('s3')

    @logger
    def get_data(self, f_name, db_enum, schema):
        filename = '{}/{}/{}.sql'.format(DW_QUERIES_DIR, schema, f_name)

        with open(filename) as f:
            raw_query = f.read()

        data = BaseETL.from_db_query(
            db_enum=db_enum,
            query=raw_query
        )

        return data

    @logger
    def clean_table(self, schema, table, enumdb):
        filecommand = "TRUNCATE TABLE {}.{}"
        raw_query = filecommand.format(schema, table)

        BaseETL.execute_command(
            db_enum=enumdb,
            encoding='UTF8',
            command=raw_query,
            commit=True
        )

    @logger(exclude='data')
    def create_table_dw(self, table_name, data):
        table = BaseETL.decode_table(data, 'LATIN-1')

        BaseETL.bulk_insert(
            table=table,
            table_name=table_name,
            db_enum=EnumDB.BI_DW,
            encoding='UTF8',
            append=False,
            commit=True,
            bucket_name='{}/clean/ods/{}'.format(self.bucket_datalake, table_name)
        )

    @logger
    def guarantee_integrity(self, db_enum, schema, f_name, f_column, dim_name, dim_column, type):
        if type == 'update':
            query = """
                    UPDATE {0}.{1}
                    SET {2} = -1
                    WHERE  NOT EXISTS (
                       SELECT 1
                       FROM   {0}.{3} d
                       WHERE  {1}.{2} = d.{4}
                       );
                    """.format(schema, f_name, f_column, dim_name, dim_column)
        else:
            query = """
                    DELETE FROM {0}.{1}
                    WHERE  NOT EXISTS (
                       SELECT 1
                       FROM   {0}.{3} d
                       WHERE  {1}.{2} = d.{4}
                       );
                    """.format(schema, f_name, f_column, dim_name, dim_column)

        BaseETL.execute_command(
            query,
            db_enum=db_enum,
            commit=True
        )
