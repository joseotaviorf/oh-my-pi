import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from hive_metastore_client import HiveMetastoreClient
from pyspark.sql.functions import split
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DataLakeMetastoreMapping
from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.hive import TableStorageDescriptorEnum
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers.databricks_consumer import (
    DatabricksConsumer,
)
from bietlejuice.jobs.composer.loaders import HiveMetastoreLoader
from bietlejuice.jobs.composer.pipeline import MetastoreExternalTablePipeline
from bietlejuice.jobs.composer.services.metastore_services import HiveMetastoreService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "create_metastore_external_table"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_all_table_partition_values(database_name, table_name):
    """
    Query the Spark metastore to get the partitions values for given table.

    :param database_name: database name
    :param table_name: table from which partitions will be fetched
    :return: List[List[str]]
    """
    databricks_consumer = DatabricksConsumer({"db": database_name}, SparkClient())
    databricks_partition_values = databricks_consumer.get_partition_values_from_table(
        table_name=table_name
    )
    formatted_partition_values = format_df_partition_values(
        df_partition_values=databricks_partition_values
    )
    return formatted_partition_values


def format_df_partition_values(df_partition_values):
    """
    Converts the df with existing partition values from Databricks Metastore to
     a list with lists of partition values.

    :param df_partition_values: spark dataframe returned from SHOW PARTITIONS command
    :type df_partition_values: pyspark.sql.DataFrame
    :rtype: List[List[str]]
    """
    if not df_partition_values or "partition" not in df_partition_values.columns:
        logger.info(
            f"m={JOB_NAME}, env={env}, database_base_name={database_base_name}, table_name={table_name},"
            " msg=No partition found in table's dataframe"
        )
        return []

    df_partitioned = df_partition_values.withColumn(
        "partitions", split(df_partition_values["partition"], "/")
    ).drop("partition")

    partition_values = []
    for row in df_partitioned.collect():
        current_partition = []
        for partition in row[0]:
            current_partition.append(partition.split("=")[1])
        partition_values.append(current_partition)

    return partition_values


def is_table_in_hive_metastore(metastore_host, hive_database_name, hive_table_name):
    """
    Checks if table already exist in hive metastore.

    :param metastore_host: hive metastore hostname
    :type metastore_host: str
    :param hive_database_name: hive metastore database name
    :type hive_database_name: str
    :param hive_table_name: table name in hive metastore
    :type hive_table_name: str
    :rtype: bool
    """
    hms_client = HiveMetastoreClient(metastore_host)
    hms_service = HiveMetastoreService(hms_client)
    hms_loader = HiveMetastoreLoader(hms_service)
    return hms_loader.is_table_in_metastore(
        database_name=hive_database_name, table_name=hive_table_name
    )


def parse_args():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="One of env values: [forno|prod]")
    parser.add_argument(
        "datalake_bucket", type=str, help="data lake bucket"
    )  # TODO: this could be got from an enum, since we won't change frequently
    parser.add_argument(
        "layer", type=str, help="One of layer values: [raw|clean|enrich|dw]"
    )
    parser.add_argument(
        "database_base_name",
        type=str,
        help="base name of metastore database. I.e. the 'source' name for raw and clean layers, and the 'source' and/or"
        " 'context' name for enrich layer",
    )
    parser.add_argument("table_name", type=str, help="table name")
    parser.add_argument(
        "partition_keys",
        type=str,
        help="the table partitions keys separated by comma. e.g. year,month,day",
    )
    parser.add_argument(
        "execution_date",
        type=str,
        help="the task execution date to infer the daily partition values",
    )

    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    env = args.env
    data_lake_bucket = args.datalake_bucket
    layer = args.layer
    database_base_name = args.database_base_name
    table_name = args.table_name
    partition_keys = args.partition_keys.split(",")
    execution_date = args.execution_date

    partition_keys = [(p_key, "string") for p_key in partition_keys]

    dt_datetime = datetime.strptime(execution_date, "%Y-%m-%d")
    partition_values = [dt_datetime.year, dt_datetime.month, dt_datetime.day]

    logger.info(
        f"m={JOB_NAME}, env={env}, datalake_bucket={data_lake_bucket}, "
        + f"layer={layer}, database_base_name={database_base_name}, "
        f"table_name={table_name}, partition_keys={partition_keys},"
        f"partition_values={partition_values}, msg=Job execution started."
    )

    dlmp = DataLakeMetastoreMapping(env, database_base_name, data_lake_bucket)
    (
        databricks_database_name,
        database_location,
        metastore_database_name,
    ) = dlmp.get_data_lake_info_from_layer(layer)

    spark_metastore_service = SparkMetastoreService(SparkClient())
    spark_table_schema = spark_metastore_service.get_table_schema(
        databricks_database_name, table_name, ignore_partition_keys=True
    )

    storage_descriptor_info = TableStorageDescriptorEnum.from_layer(layer)

    hm_confs = dbutils.secrets.get(  # noqa: F821
        "quintoandar", DatabaseEnum.HIVE_METASTORE
    )
    hm_confs_json = json.loads(hm_confs)
    hm_host = hm_confs_json["host"]

    if not is_table_in_hive_metastore(hm_host, databricks_database_name, table_name):
        partition_values = get_all_table_partition_values(
            databricks_database_name, table_name
        )

    MetastoreExternalTablePipeline(
        metastore_host=hm_host,
        database_name=metastore_database_name,
        table_name=table_name,
        database_location=database_location,
        table_schema=spark_table_schema,
        partition_keys=partition_keys,
        partition_values=partition_values,
        format_info=storage_descriptor_info,
    ).run()

    logger.info(
        f"m={JOB_NAME}, env={env}, datalake_bucket={data_lake_bucket}, "
        + f"layer={layer}, database_base_name={database_base_name}, table_name={table_name}, msg=Table created."
    )
