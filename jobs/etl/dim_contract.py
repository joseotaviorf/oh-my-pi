from jobs.base.base_etl import BaseETL, EnumDb, petl
import sys
import os
from datetime import datetime


args = sys.argv
bucket_datalake = os.environ['bi-datalake-s3-bucket']
process_name = BaseETL.get_current_filename().replace('dim_','')

if len(args) > 1:
    if args[1] == 'ODS':

        print("Start query: {}".format(datetime.now()))

        table = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query='call ebdb.list_contrato();')

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

    elif args[1] == 'DW':
        BaseETL.move_table_to_dw(
            table_name='vw_dim_contract',
            table_name_dest='dim_contract',
            enum_db_source=EnumDb.BI_ODS,
            enum_db_dest=EnumDb.BI_DW,
            append=False,
            bucket_name='{}/clean/ebdb/{}'.format(bucket_datalake, process_name),
            process_name=process_name
        )
        BaseETL.execute_command(
            'insert into dim_contract values (-1);',
            db_enum=EnumDb.BI_DW,
            commit=True
        )