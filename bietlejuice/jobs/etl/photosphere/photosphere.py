import os
import sys
from datetime import datetime

from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB

args = sys.argv
bucket_datalake = os.environ['bi-datalake-s3-bucket']
process_name = BaseETL.get_current_filename()

print("Start query: {}".format(datetime.now()))

table = BaseETL.from_db_table(
    db_enum=EnumDB.QuintoAndar_darkrum,
    table_name='Photosphere'
)

print("To ODS: {}".format(datetime.now()))

table = BaseETL.decode_table(table, 'LATIN-1')

BaseETL.to_s3(
    filename='{}.csv'.format(process_name),
    data_table=table,
    bucket_folder_path='{0}/raw/darkrum/{1}'.format(bucket_datalake, process_name),
    write_header=False
)

print("Copying files between s3 buckets: {}".format(datetime.now()))

BaseETL.copy_file_between_s3_buckets(
    bucket_source=bucket_datalake,
    bucket_destination=bucket_datalake,
    full_filename_source='raw/darkrum/{0}/{0}.csv'.format(process_name),
    full_filename_dest='clean/darkrum/{0}/{0}.csv'.format(process_name)
)
