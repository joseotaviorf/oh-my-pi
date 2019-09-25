from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers import DatabricksConsumer
from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.base.spark import BaseSparkContext
from bietlejuice.jobs.composer.base.db import DATALAKE_SQL_DIR


logger = QuintoAndarLogger("Transformer")

spark = BaseSparkContext.spark


class Transformer:
    @logger
    def __init__(self, env, source, athena_client):
        self.env = env
        self.source = source
        self.client = athena_client

    @logger
    def _get_database(self, datalake_layer):
        return "datalake_{}_{}_{}".format(self.source, datalake_layer, self.env)

    @logger
    def _get_spark_table_schema(self, datalake_layer, table_name):
        spark_table_schema = "datalake_{}_{}".format(self.source, datalake_layer)
        consumer = DatabricksConsumer({"db": spark_table_schema})
        table_schema = consumer.get_table_schema(table_name).collect()

        table_schema = OrderedDict(
            [(row["col_name"], row["col_type"].lower()) for row in table_schema]
        )
        return table_schema

    @logger
    def _get_s3_base_path(self, datalake_layer):
        return "s3://5a-datalake-{}/{}/{}/".format(
            self.env, datalake_layer, self.source
        )

    @logger
    def _get_datalake_query_file_path(self, file_name):
        return DATALAKE_SQL_DIR + "/queries/{}/{}.sql".format(self.source, file_name)

    @logger
    def create_athena_table(self, table_name, datalake_layer, partition_by=None):

        """
            Parameters:
                - table_name = table name to be created on Athena
                - datalake_layer = 'raw' or 'clean'
                - partition_by = list with columns name to partition
                   -- for example: partition_by = ['year', 'month', 'day']
        """
        database = self._get_database(datalake_layer)
        s3_base_path = self._get_s3_base_path(datalake_layer)
        table_schema = self._get_spark_table_schema(datalake_layer, table_name)

        self.client.create_external_table(
            database=database,
            table_name=table_name,
            s3_table_path=s3_base_path + table_name,
            table_schema=table_schema,
            partition_by=partition_by,
            base_format=getattr(
                TableStorageFormat, "DEFAULT_{}".format(datalake_layer.upper())
            ),
        )

    @logger
    def add_partition(self, table_name, datalake_layer, partition_by_dict):
        """
            Parameters:
                - table_name = table name to be partitioned on Athena
                - datalake_layer = 'raw' or 'clean'
                - partition_by_dict = dict with columns name and values to partition
                   -- (example) partition_by_dict = {
                       year: 2019,
                       month: 08,
                       day: 28
                   }
        """

        database = self._get_database(datalake_layer)
        self.client.add_partition(database, table_name, partition_by_dict)

    @logger
    def create_dataframe_from_datalake_sql_file(
        self, file_name, dict_format_query=None
    ):
        file = self._get_datalake_query_file_path(file_name)

        with open(file, "r") as f:
            query = f.read()
            df = spark.sql(query.format(**dict_format_query))
            return df
