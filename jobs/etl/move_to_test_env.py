from jobs.base.base_etl import BaseETL, EnumDb
import sys

args = sys.argv

if len(args) > 1:
    if args[1] == 'EBDB':

        ########################################### Lead
        BaseETL.move_table_to_dw(
            table_name='vw_Lead_test',
            table_name_dest='Lead',
            enum_db_source=EnumDb.QuintoAndar_ebdb,
            enum_db_dest=EnumDb.QuintoAndar_ebdb_test,
            append=False
        )
        BaseETL.execute_command( # needed ?
            'insert into Lead values (-1);',
            db_enum=EnumDb.QuintoAndar_ebdb_test,
            commit=True
        )

        ########################################### Imovel
        BaseETL.move_table_to_dw(
            table_name='vw_Imovel_test',
            table_name_dest='Lead',
            enum_db_source=EnumDb.QuintoAndar_ebdb,
            enum_db_dest=EnumDb.QuintoAndar_ebdb_test,
            append=False
        )
        BaseETL.execute_command( # needed ?
            'insert into Imovel values (-1);',
            db_enum=EnumDb.QuintoAndar_ebdb_test,
            commit=True
        )

        ########################################### 
        BaseETL.move_table_to_dw(
            table_name='vw_Lead_test',
            table_name_dest='Lead',
            enum_db_source=EnumDb.QuintoAndar_ebdb,
            enum_db_dest=EnumDb.QuintoAndar_ebdb_test,
            append=False
        )
        BaseETL.execute_command( # needed ?
            'insert into Lead values (-1);',
            db_enum=EnumDb.QuintoAndar_ebdb_test,
            commit=True
        )

        ###########################################
        BaseETL.move_table_to_dw(
            table_name='vw_Lead_test',
            table_name_dest='Lead',
            enum_db_source=EnumDb.QuintoAndar_ebdb,
            enum_db_dest=EnumDb.QuintoAndar_ebdb_test,
            append=False
        )
        BaseETL.execute_command( # needed ?
            'insert into Lead values (-1);',
            db_enum=EnumDb.QuintoAndar_ebdb_test,
            commit=True
        )