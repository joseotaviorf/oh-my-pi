import logging as log
import os
import sys

import pandas as pd
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb
from bietlejuice.jobs.wrappers.S3.S3_file_reader import S3FileReader

if __name__ == '__main__':
    args = sys.argv
    process_name = BaseETL.get_current_filename()
    bucket_datalake = os.environ['bi-datalake-s3-bucket']

    s3 = S3FileReader()
    files = s3.get_files_from_bucket('bi-etl-ejuice-xls2ods')
    schema = 'files'
    for f in files:
        try:
            table = pd.read_excel(f[0])
            table = table.where(pd.notnull(table), None)

            table_name = f[1]

            exists = BaseETL.table_exists(db_enum=EnumDb.BI_ODS, table_name=table_name, schema=schema)
            if not exists:
                BaseETL.create_table(
                    conn=BaseETL.get_connection(db_enum=EnumDb.BI_ODS),
                    table=table,
                    tablename=table_name,
                    schema=schema,
                    sample=100000
                )

            BaseETL.dataframe_to_ods(
                df=table,
                table_name='{}."{}"'.format(schema, table_name),
                append=False,
                encoding='utf-8'
            )

            BaseETL.to_s3(
                filename=table_name,
                data_table=table,
                bucket_folder_path='{}/raw/files/{}'.format(bucket_datalake, table_name),
                encoding='utf8',
                tmp_dir='/tmp'
            )

            # temp storing the same file on "clean" directory
            # in the future, we will need to do some cleansing in data
            BaseETL.to_s3(
                filename=table_name,
                data_table=table,
                bucket_folder_path='{}/clean/files/{}'.format(bucket_datalake, table_name),
                encoding='utf8',
                tmp_dir='/tmp'
            )

        except Exception as ex:
            log.error(ex)

    sys.stdout.close()
