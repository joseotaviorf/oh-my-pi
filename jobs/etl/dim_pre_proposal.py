from jobs.base.base_etl import BaseETL, EnumDb, petl
import sys
from datetime import datetime


args = sys.argv

if len(args) > 1:
    if args[1] == 'ODS':

        print("Start query: {}".format(datetime.now()))

        table = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query='call ebdb.list_preproposta();')

        print("To ODS: {}".format(datetime.now()))

        table = BaseETL.decode_table(table, 'LATIN-1')
        # BaseETL.to_db(
        #     data_table=table,
        #     table_name='pre_proposal',
        #     db_enum=EnumDb.BI_ODS,
        #     encoding='UTF8',
        #     append=False,
        #     commit=True,
        #     create=True
        # )

        BaseETL.bulk_insert(
            table=table,
            table_name='pre_proposal',
            db_enum=EnumDb.BI_ODS,
            encoding='UTF8',
            append=False,
            commit=True
        )

    elif args[1] == 'DW':
        BaseETL.move_table(
            table_name='vw_dim_pre_proposal',
            table_name_dest='dim_pre_proposal',
            enum_db_source=EnumDb.BI_ODS,
            enum_db_dest=EnumDb.BI_DW,
            append=False
        )
        BaseETL.execute_command(
            'insert into dim_pre_proposal values (-1);',
            db_enum=EnumDb.BI_DW,
            commit=True
        )