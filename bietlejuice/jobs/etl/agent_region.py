from jobs.base.base_etl import BaseETL, EnumDb, petl
from datetime import datetime
import sys
import os

args = sys.argv
bucket_datalake = os.environ['bi-datalake-s3-bucket']
process_name = BaseETL.get_current_filename()

print("Start query: {}".format(datetime.now()))

table = BaseETL.from_db_table(
    db_enum=EnumDb.QuintoAndar_ebdb,
    table_name='DadosAgente_Regiao'
)

print("To ODS: {}".format(datetime.now()))

table = BaseETL.decode_table(table, 'LATIN-1')

BaseETL.bulk_insert(
    table=table,
    table_name=process_name,
    db_enum=EnumDb.BI_ODS,
    encoding='UTF8',
    append=False,
    commit=True,
    bucket_name='{}/raw/ods/{}'.format(bucket_datalake, process_name)
)

BaseETL.copy_file_between_s3_buckets(
    bucket_source=bucket_datalake,
    bucket_destination=bucket_datalake,
    full_filename_source='raw/ods/{0}/{0}.csv'.format(process_name),
    full_filename_dest='clean/ods/{0}/{0}.csv'.format(process_name)
)