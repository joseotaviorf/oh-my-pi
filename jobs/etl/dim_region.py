from jobs.base.base_etl import BaseETL, EnumDb, petl
import sys
from datetime import datetime


args = sys.argv
now = datetime.now()

if len(args) > 1:
    if args[1] == 'ODS':

        print("Start query: {}".format(now))

        table = BaseETL.from_db_table(
            db_enum=EnumDb.QuintoAndar_ebdb,
            table_name='MapRegiao',
            generator=True
        ).addfield('dt_timestamp', now)

        print("To ODS: {}".format(datetime.now()))
        table = BaseETL.decode_table(table, 'LATIN-1')

        if not BaseETL.table_exists(db_enum=EnumDb.BI_ODS, table_name='region'):
            BaseETL.drop_table(db_enum=EnumDb.BI_ODS, table_name='region')
            BaseETL.to_db(
                data_table=table,
                table_name='region',
                db_enum=EnumDb.BI_ODS,
                encoding='UTF8',
                append=False,
                commit=True,
                create=True
            )
        else:
            BaseETL.bulk_insert(
                table=table,
                table_name='region',
                db_enum=EnumDb.BI_ODS,
                encoding='UTF8',
                append=True,
                commit=True
            )

    elif args[1] == 'DW':
        BaseETL.move_table(
            table_name='vw_dim_region',
            table_name_dest='dim_region',
            enum_db_source=EnumDb.BI_ODS,
            enum_db_dest=EnumDb.BI_DW,
            append=False
        )

        BaseETL.execute_command(
            'insert into dim_region values (-1);',
            db_enum=EnumDb.BI_DW,
            commit=True
        )

        BaseETL.execute_command(
            command="update dim_region set dt_timestamp = '{}' where sk_region = -1;".format(now.strftime('%Y-%m-%d')),
            db_enum=EnumDb.BI_DW,
            commit=True
        )