from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
import sys
import os


if __name__ == '__main__':
    bucket_datalake = os.environ['bi-datalake-s3-bucket']
    process_name = 'property_status_over_period'
    table_name = 'dim_{}'.format(process_name)

    BaseETL.move_table_to_dw(
        table_name='vw_{}'.format(process_name),
        table_name_dest=table_name,
        enum_db_source=EnumDB.BI_ODS,
        enum_db_dest=EnumDB.BI_DW,
        append=False,
        bucket_name='{}/clean/ods/{}'.format(bucket_datalake, table_name),
        process_name=process_name
    )

    sys.stdout.flush()
