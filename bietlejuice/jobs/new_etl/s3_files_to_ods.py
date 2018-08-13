from io import BytesIO

import boto3
import pandas as pd
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb
from bietlejuice.jobs.wrappers.S3.S3_file_reader import S3FileReader
from qa_python_utils.default_logger import logger, _logger


class S3ToODS(object):
    @logger
    def __init__(self, s3_bucket, xls_s3_bucket):
        self.files = S3FileReader().get_files_from_bucket(xls_s3_bucket)
        self.schema = 'files'
        self.s3_bucket = s3_bucket
        self.s3_client = boto3.resource('s3')

    @logger
    def move_files_to_ods(self):
        for f in self.files:
            try:
                table = pd.read_excel(f[0], skiprows=0)
                table = table.where(pd.notnull(table), None)

                table_name = f[1]
                _logger.info('m=move_files_to_ods, msg=processing table name "{}"'.format(table_name))

                _logger.info('m=move_files_to_ods, msg=checking if table exists')
                exists = BaseETL.table_exists(
                    db_enum=EnumDb.BI_ODS,
                    table_name=table_name,
                    schema=self.schema
                )
                if not exists:
                    _logger.info('m=move_files_to_ods, msg=creating table')
                    BaseETL.create_table(
                        conn=BaseETL.get_connection(db_enum=EnumDb.BI_ODS),
                        table=table,
                        tablename=table_name,
                        schema=self.schema,
                        sample=100000
                    )

                _logger.info('m=move_files_to_ods, msg=dataframe_to_ods')
                BaseETL.dataframe_to_ods(
                    df=table,
                    table_name='{}."{}"'.format(self.schema, table_name),
                    append=False,
                    encoding='utf-8'
                )

                _logger.info('m=move_files_to_ods, msg=to_s3 (raw)')
                csv_buffer_raw = BytesIO()
                table.to_csv(csv_buffer_raw, index=False, sep=',', encoding='utf-8', header=True)
                file_path = 'raw/files/{0}/{0}.csv'.format(table_name)
                self.s3_client.Object(self.s3_bucket, file_path).put(Body=csv_buffer_raw.getvalue())
                csv_buffer_raw.flush()

                # temp storing the same file on "clean" directory
                # in the future, we will need to do some cleansing in data
                _logger.info('m=move_files_to_ods, msg=to_s3 (clean)')
                csv_buffer_clean = BytesIO()
                table.to_csv(csv_buffer_clean, index=False, sep=',', encoding='utf-8', header=True)
                file_path = 'clean/files/{0}/{0}.csv'.format(table_name)
                self.s3_client.Object(self.s3_bucket, file_path).put(Body=csv_buffer_clean.getvalue())
                csv_buffer_clean.flush()

            except Exception as ex:
                _logger.error(ex)
