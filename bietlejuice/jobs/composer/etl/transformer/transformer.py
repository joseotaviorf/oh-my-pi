from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.wrappers import AthenaClient
from bietlejuice.jobs.composer.base.databricks import DatabricksConsumer
from bietlejuice.jobs.composer.base.athena import TableStorageFormat


logger = QuintoAndarLogger("Transformer")


class Transformer:
    @logger
    def __init__(self, env, source):
        self.env = env
        self.source = source

    @logger
    def create_athena_table(self, table_name, datalake_layer, partition_by=None):

        """
            Parameters:
                - table_name = table name to be created on Athena
                - datalake_layer = 'raw' or 'clean'
                - partition_by = list with columns name to partition
                   -- for example: partition_by = ['year', 'month', 'day']
        """

        # pattern schemas
        database = "datalake_{}_{}_{}".format(self.source, datalake_layer, self.env)
        spark_table_schema = "datalake_{}_{}".format(self.source, datalake_layer)
        s3_base_path = "s3://5a-datalake-{}/{}/{}/".format(
            self.env, datalake_layer, self.source
        )

        consumer = DatabricksConsumer({"db": spark_table_schema})
        table_schema = consumer.get_table_schema(table_name).collect()

        table_schema = OrderedDict(
            [(row["col_name"], row["col_type"].lower()) for row in table_schema]
        )

        AthenaClient.create_external_table(
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
        database = "datalake_{}_{}_{}".format(self.source, datalake_layer, self.env)

        AthenaClient.add_partition(database, table_name, partition_by_dict)
