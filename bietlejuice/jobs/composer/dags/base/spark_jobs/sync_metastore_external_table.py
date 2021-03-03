"""
    Synchronizes the (in-house) metastore table based on the Databricks metastore's one.

    It will:
        - sync the columns (drop or create columns)
        - check partition keys and raise an error if there is a mismatch
        - sync the partition values (drop or create partitions)
"""
import json
import logging
from argparse import ArgumentParser

from pyspark.sql.functions import split
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DataLakeMetastoreMapping
from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.hive import TableStorageDescriptorEnum
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers.databricks_consumer import (
    DatabricksConsumer,
)
from bietlejuice.jobs.composer.pipeline import MetastoreExternalTablePipeline
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "create_metastore_external_table"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_spark_metastore_table_names(database_name):
    """
    Query the Spark metastore to get all the table names for given database.

    :param database_name: database name
    :type database_name: str
    :return: List[str]
    """
    databricks_consumer = DatabricksConsumer({"db": database_name}, SparkClient())
    df_databricks_tables = databricks_consumer.get_table_names_and_sizes()
    return [row.table_name for row in df_databricks_tables.collect()]


def get_spark_metastore_table_partition_values(database_name, table_name):
    """
    Query the Spark metastore to get all the partitions values for given table.

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
            f"m={JOB_NAME}, env={env}, database_name={databricks_database_name}, table_name={table_name},"
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
        "source",
        type=str,
        help="base name of metastore database. I.e. the 'source' name for raw and clean layers, and the 'source' and/or"
        " 'context' name for enrich layer",
    )
    parser.add_argument(
        "--table-name",
        type=str,
        dest="table_name",
        required=False,
        help="table name for single sync",
    )
    parser.add_argument(
        "--all-tables",
        nargs="?",
        dest="all_tables",
        required=False,
        default=False,
        const=True,
        help="sync all tables from database",
    )

    return parser.parse_args()


def get_hive_metastore_host():
    """
    Retrieves the Hive Metastore host stored in databricks secrets

    :rtype: str
    """
    hm_confs = dbutils.secrets.get(  # noqa: F821
        "quintoandar", DatabaseEnum.HIVE_METASTORE
    )
    hm_confs_json = json.loads(hm_confs)
    return hm_confs_json["host"]


if __name__ == "__main__":
    args = parse_args()
    env = args.env
    data_lake_bucket = args.datalake_bucket
    layer = args.layer
    source = args.source
    table_name = args.table_name
    all_tables = args.all_tables

    logger.info(
        f"m={JOB_NAME}, env={env}, datalake_bucket={data_lake_bucket}, "
        f"layer={layer}, source={source}, "
        f"table_name={table_name}, all_tables={all_tables}, msg=Job execution started."
    )

    if bool(table_name) == all_tables:
        raise ValueError(
            f"m={JOB_NAME}, table_name={table_name},"
            f"all_tables={all_tables}, msg=Parameters table_name and all_tables are mutual exclusive."
        )

    dl_ms_mapping = DataLakeMetastoreMapping(env, source, data_lake_bucket)
    (
        databricks_database_name,
        database_location,
        metastore_database_name,
    ) = dl_ms_mapping.get_data_lake_info_from_layer(layer)

    table_names = []

    if all_tables:
        table_names = get_spark_metastore_table_names(
            database_name=databricks_database_name
        )
    else:
        table_names.append(table_name)

    for table in table_names:
        spark_metastore_service = SparkMetastoreService(SparkClient())
        spark_ms_table_columns = spark_metastore_service.get_table_schema(
            databricks_database_name, table, ignore_partition_keys=True
        )
        spark_ms_table_partition_keys = spark_metastore_service.get_table_partition_keys(
            database_name=databricks_database_name, table_name=table
        )

        spark_ms_table_partition_values = []
        if spark_ms_table_partition_keys:
            spark_ms_table_partition_values = get_spark_metastore_table_partition_values(
                databricks_database_name, table
            )

        MetastoreExternalTablePipeline(
            metastore_host=get_hive_metastore_host(),
            database_name=metastore_database_name,
            table_name=table,
            database_location=database_location,
            table_schema=spark_ms_table_columns,
            partition_keys=spark_ms_table_partition_keys,
            partition_values=spark_ms_table_partition_values,
            format_info=TableStorageDescriptorEnum.from_layer(layer),
        ).run()

        logger.info(
            f"m={JOB_NAME}, env={env}, datalake_bucket={data_lake_bucket}, "
            f"layer={layer}, database_base_name={databricks_database_name}, "
            f"table_name={table}, msg=Table synchronized."
        )
