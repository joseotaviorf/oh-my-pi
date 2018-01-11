import os
import sys
from datetime import datetime

from jobs.base.base_etl import BaseETL, EnumDb
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import _logger, logger

args = sys.argv
bucket_datalake = os.environ['bi-datalake-s3-bucket']
process_name = BaseETL.get_current_filename().replace('dim_', '')
old_process_name = 'pre_proposta'


@logger
def execute_etl(db_enum_src, table_src_name, table_dest_name):
    _logger.info("Start query {}: {}".format(table_src_name, datetime.now()))
    table = BaseETL.from_db_table(
        db_enum=db_enum_src,
        table_name=table_src_name)

    _logger.info("To ODS {}: {}".format(table_src_name, datetime.now()))
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
        _logger.info("Start query PreProposta: {}".format(datetime.now()))

        table = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query='call ebdb.list_preproposta();')

        _logger.info("To ODS PreProposta: {}".format(datetime.now()))

        table = BaseETL.decode_table(table, 'LATIN-1')
        BaseETL.bulk_insert(
            table=table,
            table_name=old_process_name,
            db_enum=EnumDb.BI_ODS,
            encoding='UTF8',
            append=False,
            bucket_name='{}/raw/ods/{}'.format(bucket_datalake, old_process_name)
        )

        # Godfather steps
        godf_offer_table = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_godfather,
            query='select * from business.offer;'
        )

        BaseETL.to_s3(
            filename='business_offer.csv',
            data_table=godf_offer_table,
            bucket_folder_path='{}/raw/godfather/business/offer'.format(bucket_datalake),
            write_header=False
        )

        godf_topic_table = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_godfather,
            query='select * from business.topic;'
        )

        BaseETL.to_s3(
            filename='business_topic.csv',
            data_table=godf_topic_table,
            bucket_folder_path='{}/raw/godfather/business/topic'.format(bucket_datalake),
            write_header=False
        )

        athena_client = AthenaClient(s3_bucket='5a-datalake')
        a_df = athena_client.execute_query_and_return_dataframe("""
                                                                    select distinct
                                                                        eo.*,
                                                                        go.type,
                                                                        go.first_sent_at,
                                                                        go.last_sent_at,
                                                                        gt.type as topic_type
                                                                    from datalake_raw.ebdb_offer eo
                                                                    join datalake_raw.godfather_offer go
                                                                        on eo.godfatherid = go.id
                                                                    left join datalake_raw.godfather_topic gt
                                                                        on gt.offer_id = go.id
                                                                    ;
                                                                """
                                                                )

        _logger.info("To ODS Offer: {}".format(datetime.now()))
        BaseETL.dataframe_to_db(
            df=a_df,
            table_name=process_name,
            enum_db=EnumDb.BI_ODS,
            append=False
        )

        execute_etl(EnumDb.QuintoAndar_ebdb, 'PreProposta_AUD', old_process_name + '_AUD')
        execute_etl(EnumDb.QuintoAndar_ebdb, 'CondicaoProposta', 'condition')
        execute_etl(EnumDb.QuintoAndar_ebdb, 'PreProposta_CondicaoProposta', 'pre_proposal_condition')

    elif args[1] == 'DW':
        BaseETL.move_table_to_dw(
            table_name='vw_dim_offer',
            table_name_dest='dim_{}'.format(process_name),
            enum_db_source=EnumDb.BI_ODS,
            enum_db_dest=EnumDb.BI_DW,
            append=False,
            bucket_name='{}/clean/ods/{}'.format(bucket_datalake, process_name),
            process_name='dim_{}'.format(process_name)
        )
