from jobs.base.base_etl import BaseETL, EnumDb
import sys
import os

if __name__ == '__main__':
    bucket_datalake = os.environ['bi-datalake-s3-bucket']
    table_name = 'property_status_over_period'

    BaseETL.move_table_to_dw(
        table_name='vw_{}'.format(table_name),
        table_name_dest=table_name,
        enum_db_source=EnumDb.BI_ODS,
        enum_db_dest=EnumDb.BI_DW,
        append=False,
        bucket_name='{}/clean/ods/{}'.format(bucket_datalake, table_name),
        process_name=table_name
    )

    sys.stdout.flush()
