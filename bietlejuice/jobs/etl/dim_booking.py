import os
import sys
from datetime import datetime

from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB

args = sys.argv
bucket_datalake = os.environ['bi-datalake-s3-bucket']
process_name = BaseETL.get_current_filename().replace('dim_', '')

if len(args) > 1:
    if args[1] == 'ODS':

        print("Start query: {}".format(datetime.now()))

        table = BaseETL.from_db_query(
            db_enum=EnumDB.QuintoAndar_ebdb,
            query='call ebdb.list_agendamento();')

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

    elif args[1] == 'DW':
        BaseETL.move_table_to_dw(
            table_name='vw_dim_booking',
            table_name_dest='dim_booking',
            enum_db_source=EnumDB.BI_ODS,
            enum_db_dest=EnumDB.BI_DW,
            append=False,
            bucket_name='{}/clean/ods/{}'.format(bucket_datalake, process_name),
            process_name=process_name
        )
        BaseETL.execute_command(
            'insert into dim_booking values (-1);',
            db_enum=EnumDB.BI_DW,
            commit=True
        )
        BaseETL.execute_command(
            """
            update
                dim_booking
            set
                visit_follow_up = null
            where
                visit_follow_up = ''
            """,
            db_enum=EnumDB.BI_DW,
            commit=True
        )
