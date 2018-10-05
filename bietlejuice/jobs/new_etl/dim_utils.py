import os
from datetime import datetime, date

from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from marketing_costs.fb_campaigns import FacebookCampaigns
from marketing_costs.google_campaigns import GoogleCampaigns

logger = QuintoAndarLogger('dim-utils')

dir_path = os.path.dirname(os.path.realpath(__file__))
QUERIES_DIR = os.path.join(dir_path, '../../db/datalake/queries')
now = datetime.now()


def extract_query_dim_from_ebdb_to_ods(dim_name, bucket, command, table_name=None):
    if table_name is None:
        table_name = dim_name

    logger.info("Start query: {}".format(datetime.now()))
    table = BaseETL.from_db_query(
        db_enum=EnumDB.QuintoAndar_ebdb,
        query=command
    )

    logger.info("To ODS: {}".format(datetime.now()))
    table = BaseETL.decode_table(table, 'LATIN-1')
    BaseETL.bulk_insert(
        table=table,
        table_name=table_name,
        db_enum=EnumDB.BI_ODS,
        encoding='UTF8',
        append=False,
        commit=True,
        bucket_name='{}/raw/ods/{}'.format(bucket, dim_name)
    )


# TODO: Make some of those parameters decorators
def extract_table_dim_from_ebdb_to_ods(dim_name, bucket, table_name, add_timestamp=False, copy_to_clean=True):
    logger.info("Start query: {}".format(now))
    if add_timestamp:
        table = BaseETL.from_db_table(
            db_enum=EnumDB.QuintoAndar_ebdb,
            table_name=table_name,
            generator=True
        ).addfield('dt_timestamp', now)
    else:
        table = BaseETL.from_db_table(
            db_enum=EnumDB.QuintoAndar_ebdb,
            table_name=table_name,
            generator=True
        )

    logger.info("To ODS: {}".format(datetime.now()))
    table = BaseETL.decode_table(table, 'LATIN-1')
    BaseETL.bulk_insert(
        table=table,
        table_name=dim_name,
        db_enum=EnumDB.BI_ODS,
        encoding='UTF8',
        append=False,
        commit=True,
        bucket_name='{}/raw/ods/{}'.format(bucket, dim_name)
    )
    if copy_to_clean:
        BaseETL.copy_file_between_s3_buckets(
            bucket_source=bucket,
            bucket_destination=bucket,
            full_filename_source='raw/ods/{0}/{0}.csv'.format(table_name),
            full_filename_dest='clean/ods/{0}/{0}.csv'.format(table_name)
        )


def load_dim_from_ods_to_dw(dim_name, bucket, insert_dummy=True, is_fact=False, pre_command=None, post_command=None,
                            schema_source='public', schema_dest='public'):
    table_name = ('vw_fact_{}' if is_fact else 'vw_dim_{}').format(dim_name)
    table_name_dest = ('fact_{}' if is_fact else 'dim_{}').format(dim_name)

    if pre_command is not None:
        BaseETL.execute_command(
            command=pre_command,
            db_enum=EnumDB.BI_DW,
            commit=True
        )
    BaseETL.move_table_to_dw(
        table_name='{}.{}'.format(schema_source, table_name),
        table_name_dest='{}.{}'.format(schema_dest, table_name_dest),
        enum_db_source=EnumDB.BI_ODS,
        enum_db_dest=EnumDB.BI_DW,
        append=False,
        bucket_name='{}/clean/ods/{}'.format(bucket, dim_name),
        process_name=dim_name
    )
    if insert_dummy:
        BaseETL.execute_command(
            command='insert into {} values (-1);'.format(table_name_dest),
            db_enum=EnumDB.BI_DW,
            commit=True
        )
    if post_command is not None:
        BaseETL.execute_command(
            command=post_command,
            db_enum=EnumDB.BI_DW,
            commit=True
        )


# TODO: Migrate all business dimension etl from ODS to Datalake
def load_athena_query_to_ods(dim_name, bucket, fname, append=False):
    athena = AthenaClient(bucket)
    filename = '{}/{}.sql'.format(QUERIES_DIR, fname)
    logger.info("Reading from S3: {} file:{}".format(datetime.utcnow(), filename))
    data_frame = athena.execute_file_query_and_return_dataframe(filename)

    logger.info("START - To Staging: {}".format(datetime.utcnow()))
    BaseETL.dataframe_to_db(
        enum_db=EnumDB.BI_ODS,
        df=data_frame,
        table_name=dim_name,
        encoding='utf-8',
        append=append
    )
    logger.info("END - To Staging: {}".format(datetime.utcnow()))


def load_marketing_costs(dim_name, bucket, mkt_configs):
    table_name = '{}_ads_campaigns'.format(dim_name)
    table = None
    if dim_name == 'google':
        google = GoogleCampaigns(mkt_configs['google'])
        table = google.extract_marketing_campaigns(date(2016, 1, 1))
    elif dim_name == 'facebook':
        facebook = FacebookCampaigns(mkt_configs['facebook'])
        table = facebook.extract_marketing_campaigns(date(2016, 11, 1))
    elif dim_name == 'criteo':
        table = None
        # criteo = CriteoCampaigns(mkt_configs['criteo'])
        # table = criteo.extract_marketing_campaigns(date(2017, 1, 1))

    if table is not None:
        BaseETL.bulk_insert(
            table=table,
            table_name=table_name,
            db_enum=EnumDB.BI_ODS,
            encoding='UTF8',
            append=False,
            commit=True,
            bucket_name='{}/raw/ods/{}'.format(bucket, table_name)
        )
        BaseETL.copy_file_between_s3_buckets(
            bucket_source=bucket,
            bucket_destination=bucket,
            full_filename_source='raw/ods/{0}/{0}.csv'.format(table_name),
            full_filename_dest='clean/ods/{0}/{0}.csv'.format(table_name)
        )
    else:
        logger.error("Failure to load marketing costs mc={}".format(dim_name))
