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
                BaseETL.to_s3(
                    filename=table_name,
                    data_table=table,
                    bucket_folder_path='{}/raw/files/{}'.format(self.s3_bucket, table_name),
                    encoding='utf8',
                    tmp_dir='/tmp'
                )

                # temp storing the same file on "clean" directory
                # in the future, we will need to do some cleansing in data
                _logger.info('m=move_files_to_ods, msg=to_s3 (clean)')
                BaseETL.to_s3(
                    filename=table_name,
                    data_table=table,
                    bucket_folder_path='{}/clean/files/{}'.format(self.s3_bucket, table_name),
                    encoding='utf8',
                    tmp_dir='/tmp'
                )
            except Exception as ex:
                _logger.error(ex)
