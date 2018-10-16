import time
from datetime import datetime

from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.new_etl import DATALAKE_QUERIES_DIR


class Marketing(object):
    TABLE_PARTITION_DATE = '__PARTITION_DATE__'
    TABLE_PARTITION_ACCOUNT = '__PARTITION_ACCOUNT__'

    def __init__(self, s3_bucket, execution_date, account, integration):
        self.s3_bucket = s3_bucket
        self.execution_date = execution_date
        self.account = account
        self.partition_date = self.execution_date.strftime('%Y-%m-%d')
        self.athena_client = AthenaClient(self.s3_bucket)
        self.integration = integration
        self.query_path = 'marketing/{integration}/raw_to_clean'.format(integration=self.integration)
        self.database = 'datalake_raw'

    @logger(exclude=['r_cols', 'c_cols'])
    def _move_to_clean(self, table_name, sql_file_name, r_cols, c_cols, query_path):
        key = 'clean/marketing/{integration}/{table_name}/acc={acc_partition}/' \
              'created_dt={date_partition}/{file_name}.parquet' \
            .format(
                integration=self.integration,
                table_name=table_name,
                acc_partition=self.account,
                date_partition=self.partition_date,
                file_name=int(time.mktime(datetime.now().timetuple())) * 1000
            )

        query = BaseETL.get_query_from_file_name(
            '{query_base_dir}/{query_path}/{file_name}'.format(
                query_base_dir=DATALAKE_QUERIES_DIR,
                query_path=self.query_path,
                file_name=sql_file_name))

        self.athena_client.add_partition(
            database=self.database,
            table_name=table_name,
            partition="dt='{dt}', acc='{acc}'".format(dt=self.partition_date, acc=self.account)
        )

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query.format(date=self.execution_date.strftime("%Y-%m-%d"),
                               account=self.account),
            raw_columns=r_cols,
            clean_columns=c_cols
        )
