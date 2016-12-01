from jobs.base.base_etl import BaseETL, EnumDb, petl
import sys


args = sys.argv

if len(args) > 1:
    if args[1] == 'ODS':
        list_users = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query='call ebdb.list_usuario();')

        BaseETL.to_db(
            db_enum=EnumDb.BI_ODS,
            data_table=list_users,
            table_name='usuario',
            append=False,
            create=False
        )

    elif args[1] == 'DW':
        dim = BaseETL.from_db_table(
            db_enum=EnumDb.BI_ODS,
            table_name='list_dim_user()')

        BaseETL.to_db(
            db_enum=EnumDb.BI_DW,
            data_table=dim,
            table_name='dim_user',
            append=False
        )
