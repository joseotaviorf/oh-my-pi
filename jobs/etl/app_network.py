from jobs.base.base_etl import BaseETL, EnumDb, petl
import sys
from datetime import datetime


args = sys.argv

if len(args) > 1:
    if args[1] == 'ODS':

        print("Start query: {}".format(datetime.now()))

        BaseETL.move_table(
            table_name='vw_app_network',
            table_name_dest='app_network',
            enum_db_source=EnumDb.BI_ODS,
            enum_db_dest=EnumDb.BI_ODS,
            append=False
        )

        print("To ODS: {}".format(datetime.now()))
        

    # elif args[1] == 'DW':
    #     BaseETL.move_table(
    #         table_name='vw_dim_contract',
    #         table_name_dest='dim_contract',
    #         enum_db_source=EnumDb.BI_ODS,
    #         enum_db_dest=EnumDb.BI_DW,
    #         append=False
    #     )
    #     BaseETL.execute_command(
    #         'insert into dim_contract values (-1);',
    #         db_enum=EnumDb.BI_DW,
    #         commit=True
    #     )