import boto3
from __init__ import DW_QUERIES_DIR
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb
from qa_python_utils.default_logger import _logger


class Bridge(object):
    def __init__(self):
        self.schema_name = ''
        self.bucket_datalake = '5a-datalake'
        self.s3_client = boto3.resource('s3')

    def __format_query_filename(self, filename, db_enum):
        if db_enum == EnumDb.BI_DW:
            dir = DW_QUERIES_DIR
        else:
            dir = ''
        return '{}/{}.sql'.format(dir, filename)

    def get_data(self, f_name, db_enum):
        filename = self.__format_query_filename(f_name, db_enum)
        with open(filename) as f:
            raw_query = f.read()

        data = BaseETL.from_db_query(
            db_enum=db_enum,
            query=raw_query
        )

        return data

    def clean_table(self, schema, table, enumdb):
        filecommand = "TRUNCATE TABLE {}.{}"
        raw_query = filecommand.format(schema, table)

        BaseETL.execute_command(
            db_enum=enumdb,
            encoding='UTF8',  # conn=conn,
            command=raw_query,
            commit=True
        )

    def create_table_dw(self, table_name, data):
        table = BaseETL.decode_table(data, 'LATIN-1')

        BaseETL.bulk_insert(
            table=table,
            table_name=table_name,
            db_enum=EnumDb.BI_DW,
            encoding='UTF8',
            append=False,
            commit=True,
            bucket_name='{}/clean/ods/{}'.format(self.bucket_datalake, table_name)
        )

    def guarantee_integrity(self, db_enum, schema, f_name, f_column, dim_name, dim_column):
        query = """
                DELETE FROM {0}.{1}
                WHERE  NOT EXISTS (
                   SELECT 1
                   FROM   {0}.{3} d
                   WHERE  {1}.{2} = d.{4}
                   );
                """.format(schema, f_name, f_column, dim_name, dim_column)

        _logger.info(query)

        BaseETL.execute_command(
            query,
            db_enum=db_enum,
            commit=True
        )
