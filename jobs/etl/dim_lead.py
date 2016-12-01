from jobs.base.base_etl import BaseETL, EnumDb
import sys

args = sys.argv

if len(args) > 1:
    if args[1] == 'ODS':
        listODS = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query='call ebdb.list_lead();')

        BaseETL.to_db(
            db_enum=EnumDb.BI_ODS,
            data_table=listODS,
            table_name='lead',
            append=False
        )

    elif args[1] == 'DW':
        dim = BaseETL.from_db_table(
            db_enum=EnumDb.BI_ODS,
            table_name='list_dim_lead()')

        BaseETL.to_db(
            db_enum=EnumDb.BI_DW,
            data_table=dim,
            table_name='dim_lead',
            append=False
        )
