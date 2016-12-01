from jobs.base.base_etl import BaseETL, EnumDb
import sys
from datetime import datetime


args = sys.argv

if len(args) > 1:
    if args[1] == 'ODS':

        print("Start query: {}".format(datetime.now()))

        listODS = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query="call ebdb.list_potential_listings(null);")

        print("To ODS: {}".format(datetime.now()))

        BaseETL.to_db(
            db_enum=EnumDb.BI_ODS,
            data_table=listODS,
            table_name='potential_listings',
            append=False
        )

        # call facebook ads api load costs table

        # call google adwords api load costs table

        # call unbounce api and load costs table

        # call routine to load IS workbook and load IS costs table

    elif args[1] == 'DW':
        dim = BaseETL.from_db_table(
            db_enum=EnumDb.BI_ODS,
            table_name='list_potential_listings()')

        BaseETL.to_db(
            db_enum=EnumDb.BI_DW,
            data_table=dim,
            table_name='fact_supply_potential_listings',
            append=False
        )
