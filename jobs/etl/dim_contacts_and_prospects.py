from jobs.base.base_etl import BaseETL, EnumDb
import sys

args = sys.argv

if len(args) > 1:
    if args[1] == 'ODS':
        listODS = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query='call ebdb.list_contacts_and_prospects();')

        BaseETL.to_db(
            db_enum=EnumDb.BI_ODS,
            data_table=listODS,
            table_name='contacts_and_prospects',
            append=False
        )

    elif args[1] == 'DW':
        BaseETL.move_table(
            table_name='vw_dim_contacts_and_prospects',
            table_name_dest='dim_contacts_and_prospects',
            enum_db_source=EnumDb.BI_ODS,
            enum_db_dest=EnumDb.BI_DW,
            append=False
        )
        BaseETL.execute_command(
            'insert into dim_lead values (-1);',
            db_enum=EnumDb.BI_DW,
            commit=True
        )