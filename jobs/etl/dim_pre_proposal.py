from jobs.base.base_etl import BaseETL, EnumDb, petl
import sys
import os
from datetime import datetime


args = sys.argv
bucket_datalake = os.environ['bi-datalake-s3-bucket']
process_name = BaseETL.get_current_filename().replace('dim_','')


def execute_etl(db_enum_src, table_src_name, table_dest_name):
    print("Start query {}: {}".format(table_src_name, datetime.now()))
    table = BaseETL.from_db_table(
        db_enum=db_enum_src,
        table_name=table_src_name)
    print("To ODS {}: {}".format(table_src_name, datetime.now()))
    table = BaseETL.decode_table(table, 'LATIN-1')
    BaseETL.bulk_insert(
        table=table,
        table_name=table_dest_name,
        db_enum=EnumDb.BI_ODS,
        encoding='UTF8',
        append=False,
        commit=True,
        bucket_name='{}/raw/ebdb/{}'.format(bucket_datalake, table_dest_name)
    )


if len(args) > 1:
    if args[1] == 'ODS':

        print("Start query PreProposta: {}".format(datetime.now()))

        table = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query='call ebdb.list_preproposta();')

        print("To ODS PreProposta: {}".format(datetime.now()))

        table = BaseETL.decode_table(table, 'LATIN-1')
        BaseETL.bulk_insert(
            table=table,
            table_name=process_name,
            db_enum=EnumDb.BI_ODS,
            encoding='UTF8',
            append=False,
            commit=True,
            bucket_name='{}/raw/ods/{}'.format(bucket_datalake, process_name)
        )

        execute_etl(EnumDb.QuintoAndar_ebdb, 'PreProposta_AUD', process_name + '_AUD')
        execute_etl(EnumDb.QuintoAndar_ebdb, 'CondicaoProposta', 'condition')
        execute_etl(EnumDb.QuintoAndar_ebdb, 'PreProposta_CondicaoProposta', 'pre_proposal_condition')

    elif args[1] == 'DW':
        BaseETL.move_table_to_dw(
            table_name='vw_dim_pre_proposal',
            table_name_dest='dim_pre_proposal',
            enum_db_source=EnumDb.BI_ODS,
            enum_db_dest=EnumDb.BI_DW,
            append=False,
            bucket_name='{}/clean/ods/{}'.format(bucket_datalake, process_name),
            process_name=process_name
        )
        BaseETL.execute_command(
            'insert into dim_pre_proposal values (-1);',
            db_enum=EnumDb.BI_DW,
            commit=True
        )