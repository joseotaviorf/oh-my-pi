from jobs.base.base_etl import BaseETL, EnumDb
import sys
from datetime import datetime

args = sys.argv

if len(args) > 1:
    if args[1] == 'ODS':

        print("Start query: {}".format(datetime.now()))

        listODS = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query="call ebdb.list_potential_listings_temp(null);")

        print("To ODS: {}".format(datetime.now()))

        BaseETL.to_db(
            db_enum=EnumDb.BI_ODS,
            data_table=listODS,
            table_name='potential_listings_temp',
            append=False
        ) do nothing because same script as usual

    elif args[1] == 'DW':
        BaseETL.move_table(
            table_name='vw_fact_supply_potential_listings_temp',
            table_name_dest='fact_supply_potential_listings_temp',
            enum_db_source=EnumDb.BI_ODS,
            enum_db_dest=EnumDb.BI_DW,
            append=False
        )
