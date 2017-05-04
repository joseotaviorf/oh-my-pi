import sys
from jobs.base.base_etl import BaseETL, EnumDb
from jobs.wrappers.S3.S3_file_reader import S3FileReader

if __name__ == '__main__':
    args = sys.argv
    s3 = S3FileReader()
    files = s3.get_files_from_bucket('bi-etl-ejuice-xls2ods')
    schema = 'files'
    for f in files:
        # if f[1] == 'agent_comission_hourly':
            try:
                table = s3.get_tables_from_files(f[0])
                table_name=f[1]
                exists = BaseETL.table_exists(db_enum=EnumDb.BI_ODS, table_name=table_name, schema=schema)
                if exists:
                    BaseETL.truncate_table(db_enum=EnumDb.BI_ODS, table_name=table_name, schema=schema)

                BaseETL.bulk_insert(
                    db_enum=EnumDb.BI_ODS,
                    table=table,
                    table_name=schema+'.'+f[1],
                    append=False)

            except Exception as ex:
                print(ex)
