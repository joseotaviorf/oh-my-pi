from jobs.base.base_etl import BaseETL, EnumDb
import sys

args = sys.argv

if len(args) > 1:
    if args[1] == 'ODS':

        db_source = EnumDb.QuintoAndar_ebdb
        db_dest = EnumDb.BI_ODS
        try:
            if args[2] == 'test':
                db_source = EnumDb.QuintoAndar_ebdb_test
                db_dest = EnumDb.BI_ODS_test
        except NameError:
            pass

        listODS = BaseETL.from_db_query(
            db_enum=db_source,
            query='call ebdb.list_contacts_and_prospects();')

        BaseETL.to_db(
            db_enum=db_dest,
            data_table=listODS,
            table_name='contacts_and_prospects',
            append=False
        )

    elif args[1] == 'DW':
        BaseETL.move_table_to_dw(
            table_name='vw_dim_contacts_and_prospects',
            table_name_dest='dim_contacts_and_prospects',
            enum_db_source=EnumDb.BI_ODS,
            enum_db_dest=EnumDb.BI_DW,
            append=False
        )
        BaseETL.execute_command(
            'insert into dim_contacts_and_prospects values (-1);',
            db_enum=EnumDb.BI_DW,
            commit=True
        )