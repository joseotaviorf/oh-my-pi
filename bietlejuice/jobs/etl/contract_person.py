import os
import sys
from datetime import datetime

from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB

args = sys.argv
bucket_datalake = os.environ['bi-datalake-s3-bucket']
process_name = BaseETL.get_current_filename()

if len(args) > 1:
    if args[1] == 'ODS':
        print("Start query: {}".format(datetime.now()))

        table = BaseETL.from_db_query(
            db_enum=EnumDB.QuintoAndar_ebdb,
            query='call ebdb.list_contrato_pessoa();')

        print("To ODS: {}".format(datetime.now()))

        table = BaseETL.decode_table(table, 'LATIN-1')
        BaseETL.bulk_insert(
            table=table,
            table_name=process_name,
            db_enum=EnumDB.BI_ODS,
            encoding='UTF8',
            append=False,
            commit=True,
            bucket_name='{}/raw/ods/{}'.format(bucket_datalake, process_name)
        )
