import sys
from jobs.base.base_etl import BaseETL, EnumDb
from jobs.wrappers.S3.S3_file_reader import S3FileReader
import os


if __name__ == '__main__':
    args = sys.argv
    process_name = BaseETL.get_current_filename()
    bucket_datalake = os.environ['bucket_datalake']

    s3 = S3FileReader()
    files = s3.get_files_from_bucket('bi-etl-ejuice-xls2ods')
    schema = 'files'
    for f in files:
        try:
            table = s3.get_tables_from_files(f[0])
            table_name=f[1]

            exists = BaseETL.table_exists(db_enum=EnumDb.BI_ODS, table_name=table_name, schema=schema)
            if exists:
                BaseETL.truncate_table(db_enum=EnumDb.BI_ODS, table_name=table_name, schema=schema)

            BaseETL.to_db(db_enum=EnumDb.BI_ODS,
                          data_table=table,
                          table_name=f[1],
                          schema=schema,
                          create=not exists,
                          append=False)

            BaseETL.to_s3(
                filename=table_name,
                data_table=table,
                bucket_folder_path='{}/raw/files/{}'.format(bucket_datalake, f[1]),
                encoding='utf8',
                tmp_dir='/tmp'
            )

            # temp storing the same file on "clean" directory
            # in the future, we will need to do some cleansing in data
            BaseETL.to_s3(
                filename=table_name,
                data_table=table,
                bucket_folder_path='{}/clean/files/{}'.format(bucket_datalake, f[1]),
                encoding='utf8',
                tmp_dir='/tmp'
            )


        except Exception as ex:
            print(ex)
