import os
from datetime import datetime

from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import _logger

from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb

dir_path = os.path.dirname(os.path.realpath(__file__))
QUERIES_DIR = os.path.join(dir_path, '../../db/2.datalake/queries')
now = datetime.now()


def extract_query_dim_from_ebdb_to_ods(dim_name, bucket, command, table_name=None):
    if table_name is None:
        table_name = dim_name

    _logger.info("Start query: {}".format(datetime.now()))
    table = BaseETL.from_db_query(
        db_enum=EnumDb.QuintoAndar_ebdb,
        query=command
    )

    _logger.info("To ODS: {}".format(datetime.now()))
    table = BaseETL.decode_table(table, 'LATIN-1')
    BaseETL.bulk_insert(
        table=table,
        table_name=table_name,
        db_enum=EnumDb.BI_ODS,
        encoding='UTF8',
        append=False,
        commit=True,
        bucket_name='{}/raw/ods/{}'.format(bucket, dim_name)
    )


def extract_table_dim_from_ebdb_to_ods(dim_name, bucket, table_name, add_timestamp=False, copy_to_clean=True):
    _logger.info("Start query: {}".format(now))
    if add_timestamp:
        table = BaseETL.from_db_table(
            db_enum=EnumDb.QuintoAndar_ebdb,
            table_name=table_name,
            generator=True
        ).addfield('dt_timestamp', now)
    else:
        table = BaseETL.from_db_table(
            db_enum=EnumDb.QuintoAndar_ebdb,
            table_name=table_name,
            generator=True
        )

    _logger.info("To ODS: {}".format(datetime.now()))
    table = BaseETL.decode_table(table, 'LATIN-1')
    BaseETL.bulk_insert(
        table=table,
        table_name=dim_name,
        db_enum=EnumDb.BI_ODS,
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


def load_athena_query_to_ods(dim_name, bucket, fname, append=False):
    athena = AthenaClient(bucket)
    filename = '{}/{}.sql'.format(QUERIES_DIR, fname)
    _logger.info("Reading from S3: {} file:{}".format(datetime.utcnow(), filename))
    data_frame = athena.execute_file_query_and_return_dataframe(filename)

    _logger.info("START - To Staging: {}".format(datetime.utcnow()))
    BaseETL.dataframe_to_db(
        enum_db=EnumDb.BI_ODS,
        df=data_frame,
        table_name=dim_name,
        encoding='utf-8',
        append=append
    )
    _logger.info("END - To Staging: {}".format(datetime.utcnow()))


def load_dim_from_ods_to_dw(dim_name, bucket, insert_dummy=True, is_fact=False, pre_command=None, post_command=None,
                            schema_source='public', schema_dest='public'):
    table_name = ('vw_fact_{}' if is_fact else 'vw_dim_{}').format(dim_name)
    table_name_dest = ('fact_{}' if is_fact else 'dim_{}').format(dim_name)

    if pre_command is not None:
        BaseETL.execute_command(
            command=pre_command,
            db_enum=EnumDb.BI_DW,
            commit=True
        )
    BaseETL.move_table_to_dw(
        table_name='{}.{}'.format(schema_source, table_name),
        table_name_dest='{}.{}'.format(schema_dest, table_name_dest),
        enum_db_source=EnumDb.BI_ODS,
        enum_db_dest=EnumDb.BI_DW,
        append=False,
        bucket_name='{}/clean/ods/{}'.format(bucket, dim_name),
        process_name=dim_name
    )
    if insert_dummy:
        BaseETL.execute_command(
            command='insert into {} values (-1);'.format(table_name_dest),
            db_enum=EnumDb.BI_DW,
            commit=True
        )
    if post_command is not None:
        BaseETL.execute_command(
            command=post_command,
            db_enum=EnumDb.BI_DW,
            commit=True
        )


def load_dim_from_ods_to_staging(dim_name, insert_dummy=True, is_fact=False, pre_command=None, post_command=None,
                                 schema_source='public', schema_dest='staging'):
    table_name = ('vw_fact_{}' if is_fact else 'vw_dim_{}').format(dim_name)
    table_name_dest = ('fact_{}' if is_fact else 'dim_{}').format(dim_name)

    if pre_command is not None:
        BaseETL.execute_command(
            command=pre_command,
            db_enum=EnumDb.BI_ODS,
            commit=True
        )
    BaseETL.execute_command(
        command='truncate {}.{}'.format(schema_dest, table_name_dest),
        db_enum=EnumDb.BI_ODS,
        commit=True
    )
    BaseETL.execute_command(
        command='insert into {}.{} select * from {}.{}'.format(schema_dest, table_name_dest, schema_source, table_name),
        db_enum=EnumDb.BI_ODS,
        commit=True
    )
    if insert_dummy:
        BaseETL.execute_command(
            command='insert into {}.{} values (-1);'.format(schema_dest, table_name_dest),
            db_enum=EnumDb.BI_ODS,
            commit=True
        )
    if post_command is not None:
        BaseETL.execute_command(
            command=post_command,
            db_enum=EnumDb.BI_ODS,
            commit=True
        )


def load_dim_from_staging_to_dw(dim_name, bucket, is_fact=False, schema_source='staging', schema_dest='public'):
    table_name = ('fact_{}' if is_fact else 'dim_{}').format(dim_name)

    BaseETL.move_table_to_dw(
        table_name='{}.{}'.format(schema_source, table_name),
        table_name_dest='{}.{}'.format(schema_dest, table_name),
        enum_db_source=EnumDb.BI_ODS,
        enum_db_dest=EnumDb.BI_DW,
        append=False,
        bucket_name='{}/clean/ods/{}'.format(bucket, dim_name),
        process_name=dim_name
    )


def materialize_view_ods(view_name, bucket, append=False):
    table = BaseETL.from_db_query(
        db_enum=EnumDb.BI_ODS,
        query='select * from vw_{}'.format(view_name))

    print("To ODS: {}".format(datetime.now()))

    BaseETL.bulk_insert(
        table=table,
        table_name=view_name,
        db_enum=EnumDb.BI_ODS,
        encoding='UTF8',
        append=append,
        commit=True,
        bucket_name='{}/raw/ods/{}'.format(bucket, view_name)
    )


def load_athena_file_query_to_ods(table_name, file_name, bucket, append=False):
    athena = AthenaClient(bucket)
    df = athena.execute_file_query_and_return_dataframe('{}/{}'.format(QUERIES_DIR, file_name))
    __df_to_db(enum_db=EnumDb.BI_ODS, df=df, table_name=table_name, append=append)


def __df_to_db(enum_db, df, table_name, append=False):
    _logger.info('m=__df_to_db, msg=sending data frame to db')
    BaseETL.dataframe_to_db(
        enum_db=enum_db,
        df=df,
        table_name=table_name,
        encoding='utf-8',
        append=append
    )
