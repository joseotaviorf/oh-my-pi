import sys
from jobs.base.base_etl import BaseETL, EnumDb
from jobs.wrappers.S3.S3_file_reader import S3FileReader

if __name__ == '__main__':
    args = sys.argv
    s3 = S3FileReader()
    files = s3.get_files_from_bucket('bi-etl-ejuice-xls2ods')
    schema = 'files'
    for f in files:
        try:
            table = s3.get_tables_from_files(f[0])
            BaseETL.drop_table(db_enum=EnumDb.BI_ODS, table_name=f[1], schema=schema)
            BaseETL.to_db(db_enum=EnumDb.BI_ODS,
                          data_table=table,
                          table_name=f[1],
                          schema=schema,
                          create=True,
                          append=False)
        except Exception as ex:
            print(ex)
