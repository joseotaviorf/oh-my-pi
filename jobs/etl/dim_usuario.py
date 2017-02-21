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
        BaseETL.move_table(
            table_name='vw_dim_user',
            table_name_dest='dim_user',
            enum_db_source=EnumDb.BI_ODS,
            enum_db_dest=EnumDb.BI_DW,
            append=False
        )
        BaseETL.execute_command(
            "insert into dim_user (sk_user) values (-1);",
            db_enum=EnumDb.BI_DW,
            commit=True
        )