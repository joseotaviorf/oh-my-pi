from jobs.base.base_etl import BaseETL, EnumDb, petl
import sys


args = sys.argv

if len(args) > 1:
    if args[1] == 'ODS':
        table = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query='call ebdb.list_marketing_attribution();')

        BaseETL.to_db(
            db_enum=EnumDb.BI_ODS,
            data_table=table,
            table_name='marketing_attribution',
            append=False,
            create=False
        )

    elif args[1] == 'DW':
        dim = BaseETL.from_db_table(
            db_enum=EnumDb.BI_ODS,
            table_name='list_dim_marketing_attribution()')

        BaseETL.to_db(
            db_enum=EnumDb.BI_DW,
            data_table=dim,
            table_name='dim_marketing_attribution',
            append=False
        )
