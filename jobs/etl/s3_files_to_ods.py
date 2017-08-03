import sys
from jobs.base.base_etl import BaseETL, EnumDb
from jobs.wrappers.S3.S3_file_reader import S3FileReader
import os
import logging as log


if __name__ == '__main__':
    args = sys.argv
    process_name = BaseETL.get_current_filename()
    bucket_datalake = os.environ['bi-datalake-s3-bucket']

    s3 = S3FileReader()
    files = s3.get_files_from_bucket('bi-etl-ejuice-xls2ods')
    schema = 'files'
    # files = list(files)
    for f in files:
        try:
            table = s3.get_tables_from_files(f[0])
            table_name=f[1]

            exists = BaseETL.table_exists(db_enum=EnumDb.BI_ODS, table_name=table_name, schema=schema)
            if not exists:
                BaseETL.create_table(
                    conn=BaseETL.get_connection(db_enum=EnumDb.BI_ODS),
                    table=table,
                    tablename=table_name,
                    schema=schema,
                    sample=100000
                )

            BaseETL.bulk_insert(
                db_enum=EnumDb.BI_ODS,
                table=table,
                table_name='{}."{}"'.format(schema, table_name),
                append=False,
                encoding='utf-8')

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