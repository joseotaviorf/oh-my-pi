from jobs.base.base_etl import BaseETL, EnumDb
import sys
from datetime import datetime


args = sys.argv

if len(args) > 1:
    if args[1] == 'ODS':

        print("Start query: {}".format(datetime.now()))

        listODS = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query="call ebdb.list_property_scheduling();")

        print("To ODS: {}".format(datetime.now()))

        BaseETL.bulk_insert(
            table=listODS,
            table_name='property_scheduling',
            db_enum=EnumDb.BI_ODS,
            append=False,
            commit=True
        )

    elif args[1] == 'DW':
        BaseETL.move_table(
            table_name='vw_fact_liquidity_property_scheduling',
            table_name_dest='fact_liquidity_property_scheduling',
            enum_db_source=EnumDb.BI_ODS,
            enum_db_dest=EnumDb.BI_DW,
            append=False
        )
