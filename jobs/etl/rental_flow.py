from jobs.base.base_etl import BaseETL, EnumDb
from datetime import datetime
import os

process_name = BaseETL.get_current_filename()
bucket_datalake = os.environ['bucket_datalake']

print("Start query: {}".format(datetime.now()))

table = BaseETL.from_db_table(
db_enum=EnumDb.QuintoAndar_ebdb,
table_name='FluxoLocacao')

print("To ODS: {}".format(datetime.now()))

table = BaseETL.decode_table(table, 'LATIN-1')

BaseETL.bulk_insert(
    table=table,
    table_name=process_name,
    db_enum=EnumDb.BI_ODS,
    encoding='UTF8',
    append=False,
    commit=True,
    bucket_name='{}/raw/ebdb/{}'.format(bucket_datalake, process_name)
)

BaseETL.copy_file_between_s3_buckets(
    bucket_source=bucket_datalake,
    bucket_destination=bucket_datalake,
    full_filename_source='raw/ebdb/{0}/{0}.csv'.format(process_name),
    full_filename_dest='clean/ebdb/{0}/{0}.csv'.format(process_name)
)