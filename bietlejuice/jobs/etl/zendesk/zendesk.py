from abc import abstractmethod
import petl
import boto3
import os
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR, DW_QUERIES_DIR
from bietlejuice.jobs.base.enum_db import EnumDB

logger = QuintoAndarLogger('Zendesk')


class Zendesk(object):

    @logger
    def __init__(self, s3_bucket, execution_date):
        self.s3_bucket = s3_bucket
        self.execution_date = execution_date.strftime("%Y-%m-%d")
        data_acc_aws_access_key_id = os.environ.get('DATA_ACC_AWS_ACCESS_KEY_ID')
        data_acc_aws_secret_access_key = os.environ.get('DATA_ACC_AWS_SECRET_ACCESS_KEY')
        self.athena_client = AthenaClient(self.s3_bucket, data_acc_aws_access_key_id, data_acc_aws_secret_access_key)
        if data_acc_aws_access_key_id is not None and data_acc_aws_secret_access_key is not None:
            self.s3_resource = boto3.resource('s3', aws_access_key_id=data_acc_aws_access_key_id, aws_secret_access_key=data_acc_aws_secret_access_key)
        else:
            self.s3_resource = boto3.resource('s3')

    @abstractmethod
    def move_to_clean(self):
        raise NotImplementedError('m=move_to_clean, msg=method not implemented')

    @logger
    def _upsert_single_partition(self, class_, bucket_type, integration_name=None):
        if bucket_type not in ('raw', 'clean'):
            raise ValueError('m=_upsert_single_partition, bucket_type={}, msg=invalid bucket type'.format(bucket_type))

        if bucket_type != 'raw':
            self.athena_client.upsert_single_partition(
                bucket_folder_path='{}/{}/{}/{}'.format(self.s3_bucket,
                                                        bucket_type,
                                                        # a different folder for each integration made in Stitch
                                                        integration_name if bucket_type == 'raw' else 'zendesk',
                                                        class_.value),
                database='datalake_{}'.format(bucket_type),
                table='zendesk_{}'.format(class_.value),
                partition_name='dt_extracted' if bucket_type == 'clean' else 'dt',
                partition_value=self.execution_date
            )

    def _move_to_clean_partitioned(self, class_, r_cols, c_cols):

        logger.info('m=_move_to_clean_partitioned, class_={}, \nr_cols={}, \nc_cols={}'
                    .format(class_, str(r_cols), str(c_cols)))

        key = 'clean/zendesk/{0}/dt_extracted={1}/{1}.parq'.format(class_.value, self.execution_date)
        self._move_to_clean(
            class_=class_,
            key=key,
            r_cols=r_cols,
            c_cols=c_cols,
            execution_date=self.execution_date
        )

    def _move_to_clean(self, class_, key, r_cols, c_cols, **params):

        logger.info('m=_move_to_clean, class_={}, key={}, \nr_cols={}, \nc_cols={}, \n**params={}'
                    .format(class_, key, str(r_cols), str(c_cols), params))

        query = BaseETL.get_query_from_file_name(
            '{}/zendesk/{}.sql'.format(DATALAKE_QUERIES_DIR, class_.value)
        )

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query.format(**params),
            raw_columns=r_cols,
            clean_columns=c_cols
        )

    @logger
    def _move_to_staging(self, class_, sk_field):

        conn = BaseETL.get_connection(db_enum=EnumDB.BI_DW,
                                      encoding='utf-8')

        query = BaseETL.get_query_from_file_name(
            '{}/zendesk/{}.sql'.format(DATALAKE_QUERIES_DIR, class_.value)
        ).format(extraction_date=self.execution_date)
        logger.info('m=_move_to_prod, query={}, msg=Getting data from staging(DW)'.format(query))

        df = self.athena_client.execute_query_and_return_dataframe(query)
        table_data = petl.fromdataframe(df)

        BaseETL.bulk_insert(
            table=table_data,
            db_enum=EnumDB.BI_DW,
            table_name='staging.zendesk_{}'.format(class_.value),
            encoding='utf-8',
            append=False,
            commit=False,
            conn=conn
        )

        delete_query = BaseETL.get_query_from_file_name(
            '{}/staging/zendesk/delete_old_entries.sql'.format(DW_QUERIES_DIR)
        ).format(table_name=class_.value, sk_field=sk_field)
        logger.info('m=_move_to_prod, delete_query={}, msg=Deleting old entries into staging(DW)'.format(delete_query))

        self.__delete_old_entries(delete_query, True, conn)

    @logger
    def _move_to_prod(self, class_, sk_field):

        conn = BaseETL.get_connection(db_enum=EnumDB.BI_DW,
                                      encoding='utf-8')

        delete_query = BaseETL.get_query_from_file_name(
            '{}/zendesk/delete_old_entries.sql'.format(DW_QUERIES_DIR)
        ).format(table_name=class_.value, sk_field=sk_field)
        logger.info('m=_move_to_prod, delete_query={}, msg=Deleting old entries into prod(DW)'.format(delete_query))

        self.__delete_old_entries(delete_query, False, conn)

        query = 'select distinct * from staging.zendesk_{};'.format(class_.value)
        logger.info('m=_move_to_prod, query={}, msg=Getting data from prod(DW)'.format(query))

        table_data = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query=query,
            encoding='utf-8',
            conn=conn
        )

        BaseETL.bulk_insert(
            table=table_data,
            db_enum=EnumDB.BI_DW,
            table_name='zendesk.{}'.format(class_.value),
            encoding='utf-8',
            append=True,
            commit=True,
            conn=conn
        )

    @staticmethod
    @logger
    def __delete_old_entries(delete_query, commit, conn=False):

        BaseETL.execute_command(
            db_enum=EnumDB.BI_DW,
            command=delete_query,
            commit=commit,
            conn=conn,
            encoding='utf-8'
        )
