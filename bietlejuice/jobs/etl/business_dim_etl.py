from datetime import datetime

from qa_python_utils import QuintoAndarLogger

from __init__ import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from dim_etl import DimensionETL

logger = QuintoAndarLogger('BusinessDimensionETL')


class BusinessDimensionETL(DimensionETL):

    @logger
    def __init__(self, bucket, now=datetime.now()):
        super(BusinessDimensionETL, self).__init__(bucket=bucket, now=now)

    @logger
    def extract_query_dim_from_ebdb_to_ods(self, dim_name, command, table_name=None):

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
            bucket_name='{}/raw/ods/{}'.format(self.bucket, dim_name)
        )

    # TODO: Make some of those parameters decorators
    @logger
    def extract_table_dim_from_ebdb_to_ods(self, dim_name, table_name, add_timestamp=False, copy_to_clean=True):
        logger.info("Start query: {}".format(self.now))
        if add_timestamp:
            table = BaseETL.from_db_table(
                db_enum=EnumDB.QuintoAndar_ebdb,
                table_name=table_name,
                generator=True
            ).addfield('dt_timestamp', self.now)
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
            bucket_name='{}/raw/ods/{}'.format(self.bucket, dim_name)
        )
        if copy_to_clean:
            BaseETL.copy_file_between_s3_buckets(
                bucket_source=self.bucket,
                bucket_destination=self.bucket,
                full_filename_source='raw/ods/{0}/{0}.csv'.format(table_name),
                full_filename_dest='clean/ods/{0}/{0}.csv'.format(table_name)
            )

    @logger
    def load_dim_from_ods_to_dw(self, dim_name, insert_dummy=True, is_fact=False, pre_command=None, post_command=None):
        table_name = ('vw_fact_{}' if is_fact else 'vw_dim_{}').format(dim_name)
        table_name_dest = ('fact_{}' if is_fact else 'dim_{}').format(dim_name)

        if pre_command is not None:
            BaseETL.execute_command(
                command=pre_command,
                db_enum=EnumDB.BI_DW,
                commit=True
            )

        BaseETL.move_table_to_dw(
            table_name=table_name,
            table_name_dest=table_name_dest,
            enum_db_source=EnumDB.BI_ODS,
            enum_db_dest=EnumDB.BI_DW,
            append=False,
            bucket_name='{}/clean/ods/{}'.format(self.bucket, dim_name),
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
    @logger
    def load_athena_file_query_to_ods(self, table_name, file_name, append=False):
        df = self.athena.execute_file_query_and_return_dataframe('{}/{}'.format(DATALAKE_QUERIES_DIR, file_name))
        self.__df_to_db(enum_db=EnumDB.BI_ODS, df=df, table_name=table_name, append=append)

    @logger
    def materialize_view_ods(self, view_name, append=False):
        table = BaseETL.from_db_query(
            db_enum=EnumDB.BI_ODS,
            query='select * from vw_{}'.format(view_name))

        print("To ODS: {}".format(datetime.now()))

        BaseETL.bulk_insert(
            table=table,
            table_name=view_name,
            db_enum=EnumDB.BI_ODS,
            encoding='UTF8',
            append=append,
            commit=True,
            bucket_name='{}/raw/ods/{}'.format(self.bucket, view_name)
        )

    @logger
    def load_athena_raw_query_to_ods(self, table_name, query, append=False):
        df = self.athena.execute_query_and_return_dataframe(query)
        self.__df_to_db(enum_db=EnumDB.BI_ODS, df=df, table_name=table_name, append=append)

    @logger
    def __df_to_db(self, enum_db, df, table_name, append=False):
        logger.info('m=__df_to_db, msg=sending data frame to db')
        BaseETL.dataframe_to_db(
            enum_db=enum_db,
            df=df,
            table_name=table_name,
            encoding='utf-8',
            append=append
        )
        logger.info("END - To Staging: {}".format(datetime.utcnow()))
