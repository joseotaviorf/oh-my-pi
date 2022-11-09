import logging
from argparse import ArgumentParser
from collections import OrderedDict
from multiprocessing.dummy import Pool

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.athena import TableStorageFormat
from bietlejuice.base.pipeline import EnvironmentEnum
from bietlejuice.clients.db_clients import AthenaClient, SparkClient
from bietlejuice.consumers.db_consumers import DatabricksConsumer
from bietlejuice.services.metastore_services import (
    AthenaMetastoreService,
    SparkMetastoreService,
)

JOB_NAME = "create_external_tables"
NB_THREADS = 16

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

parser = ArgumentParser(description=JOB_NAME)
parser.add_argument("env")
parser.add_argument("athena_query_result_location")
parser.add_argument("datalake_layer")
parser.add_argument("bucket")
parser.add_argument("source")
parser.add_argument("--tables", nargs="+", dest="tables", required=False)
parser.add_argument(
    "--all", nargs="?", dest="all_flag", required=False, default=False, const=True
)


class Transformer:
    def __init__(self, env, source, bucket, athena_metastore_service):
        self.env = env
        self.source = source
        self.bucket = bucket
        self.athena_metastore_service = athena_metastore_service

        # Forno is under new AWS accounts, then use new structure
        # Prod is temporarily under old AWS account and will be migrated soon, then this
        # if clause should be removed
        if self.env == EnvironmentEnum.FORNO:
            self.schema_suffix = ""
        else:
            self.schema_suffix = f"_{env}"

    def _generate_spark_schema(self, datalake_layer):
        return f"datalake_{self.source}_{datalake_layer}"

    def _get_spark_table_schema(self, datalake_layer, table_name):
        spark_table_schema = self._generate_spark_schema(datalake_layer)
        spark_sql_client = SparkClient()
        consumer = DatabricksConsumer({"db": spark_table_schema}, spark_sql_client)
        table_schema = consumer.get_table_schema(table_name).collect()
        table_schema = OrderedDict(
            [(row["col_name"], row["col_type"].lower()) for row in table_schema]
        )
        return table_schema

    @logger
    def overwrite_athena_table(self, table_name, datalake_layer):
        table_location = (
            f"s3://{self.bucket}/{datalake_layer}/{self.source}/{table_name}"
        )
        database = f"datalake_{self.source}_{datalake_layer}{self.schema_suffix}"
        table_schema = self._get_spark_table_schema(datalake_layer, table_name)

        self.athena_metastore_service.drop_table(database, table_name)
        self.athena_metastore_service.create_external_table(
            database_name=database,
            table_name=table_name,
            table_location=table_location,
            table_schema=table_schema,
            partition_cols=None,
            format_options=getattr(
                TableStorageFormat, "DEFAULT_{}".format(datalake_layer.upper())
            ),
        )


@logger
def create_external_table(args):
    transformer, datalake_layer, table_name = args
    transformer.overwrite_athena_table(table_name, datalake_layer)
    logger.info(
        "m=create_external_table, table={}, msg=Finished creating table.".format(
            table_name
        )
    )


if __name__ == "__main__":
    args = parser.parse_args()
    env = args.env
    athena_query_result_location = args.athena_query_result_location
    datalake_layer = args.datalake_layer
    bucket = args.bucket
    source = args.source
    tables = args.tables
    all_flag = args.all_flag

    logger.info(
        "m=__main__, env={}, datalake_layer={}, source={}, tables={}, all={}, "
        "msg=Job execution started".format(
            env, datalake_layer, source, tables, all_flag
        )
    )
    athena_metastore_service = AthenaMetastoreService(
        AthenaClient(athena_query_result_location)
    )
    transformer = Transformer(env, source, bucket, athena_metastore_service)
    if not all_flag and not tables:
        logger.warning("m=__main__, msg=No tables or all flag passed, nothing to do.")
    else:
        logger.info("m=__main__, msg=Creating external tables...")
        if all_flag:
            spark_metastore_service = SparkMetastoreService(SparkClient())
            dbName = transformer._generate_spark_schema(datalake_layer)
            tables = spark_metastore_service.get_table_names(dbName)
        with Pool(NB_THREADS) as p:
            p.map(
                create_external_table,
                [(transformer, datalake_layer, table) for table in tables],
            )
        logger.info("m=__main__, msg=External tables were created successfully.")
