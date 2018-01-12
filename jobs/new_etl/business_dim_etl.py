from datetime import datetime, date
from jobs.base.base_etl import BaseETL, EnumDb
from dim_etl import DimensionETL
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger


class BusinessDimensionETL(DimensionETL):

    def __init__(self, bucket, now):
        self.bucket = bucket
        self.now = now
        self.athena = AthenaClient(bucket)

    def extract_query_dim_from_ebdb_to_ods(self, dim_name, command, table_name=None):

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
            bucket_name='{}/raw/ods/{}'.format(self.bucket, dim_name)
        )

    # TODO: Make some of those parameters decorators
    def extract_table_dim_from_ebdb_to_ods(self, dim_name, table_name, add_timestamp=False, copy_to_clean=True):
        _logger.info("Start query: {}".format(self.now))
        if add_timestamp:
            table = BaseETL.from_db_table(
                db_enum=EnumDb.QuintoAndar_ebdb,
                table_name=table_name,
                generator=True
            ).addfield('dt_timestamp', self.now)
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
            append=True,
            commit=True,
            bucket_name='{}/raw/ods/{}'.format(self.bucket, dim_name)
        )
        if copy_to_clean:
            BaseETL.copy_file_between_s3_buckets(
                bucket_source=self.bucket,
                bucket_destination=self.bucket,
                full_filename_source='raw/ods/{0}/{0}.csv'.format(table_name),
                full_filename_dest='clean/ods/{0}/{0}.csv'.format(table_name)
            )

    def load_dim_from_ods_to_dw(self, dim_name, insert_dummy=True, is_fact=False, pre_command=None, post_command=None):
        if is_fact:
            table_name = 'vw_fact_{}'.format(dim_name)
            table_name_dest = 'fact_{}'.format(dim_name)
        else:
            table_name = 'vw_dim_{}'.format(dim_name)
            table_name_dest = 'dim_{}'.format(dim_name)

        if pre_command is not None:
            BaseETL.execute_command(
                command=pre_command,
                db_enum=EnumDb.BI_DW,
                commit=True
            )
        BaseETL.move_table_to_dw(
            table_name=table_name,
            table_name_dest=table_name_dest,
            enum_db_source=EnumDb.BI_ODS,
            enum_db_dest=EnumDb.BI_DW,
            append=False,
            bucket_name='{}/clean/ods/{}'.format(self.bucket, dim_name),
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

    # TODO: Migrate all business dimension etl from ODS to Datalake
    def load_athena_query_to_ods(self, dim_name, file_name, append=False):
        _logger.info("Reading from S3: {}".format(datetime.utcnow()))
        data_frame = self.athena.execute_file_query_and_return_dataframe(file_name)

        _logger.info("START - To Staging: {}".format(datetime.utcnow()))
        BaseETL.dataframe_to_db(
            enum_db=EnumDb.BI_ODS,
            df=data_frame,
            table_name=dim_name,
            encoding='utf-8',
            append=append
        )
        _logger.info("END - To Staging: {}".format(datetime.utcnow()))
