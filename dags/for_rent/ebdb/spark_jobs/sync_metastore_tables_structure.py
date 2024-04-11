import json
import logging
from argparse import ArgumentParser
from functools import partial

from hive_metastore_client import HiveMetastoreClient
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db.database_enum import DatabaseEnum
from bietlejuice.base.hive import TableStorageDescriptorEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.spark.base_spark import BaseSparkContext
from bietlejuice.base.spark.spark_metastore_helper import SparkMetastoreHelper
from bietlejuice.loaders.hive_metastore_loader import HiveMetastoreLoader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services.hive_metastore_service import (
    HiveMetastoreService,
)

JOB_NAME = "sync_metastore_tables_structure"

logging.getLogger("py4j").setLevel(logging.ERROR)
driver_logger = QuintoAndarLogger(JOB_NAME)


def update_table_structure(
    hive_ms_loader: HiveMetastoreLoader,
    database_name: str,
    database_location: str,
    storage_description: str,
    table_name: str,
    columns: list,
    partition_keys: list,
):
    """
    Updates columns and partition keys of a single table in Hive Metastore, dropping
    or creating them according to the values provided. Used for multiple concurrent
    requests that share the same Hive Metastore Loader object.
    Args:
        hive_ms_loader (HiveMetastoreLoader): Hive Metastore Loader object
        database_name (str): Name of the database from Databricks Metastore that
            contains the table(s) which partitions will be updated in Hive Metastore.
        database_location (str): File system location of the Spark database.
        storage_description (str): Storage format description for Hive Metastore table.
        table_name (str): Name of the table which structure will be updated in Hive
            Metastore.
        columns (str): List of columns that will be updated in Hive Metastore.
        partition_keys (List[str]): List of partition keys as strings.
    """
    # logs were not being register in parallel with logger, thus using print
    print(
        f"m={JOB_NAME}, database_name={database_name}, table_name={table_name}, "
        f"columns={columns}, partition_keys={partition_keys}, "
        f"msg=Starting table schema and partition keys update"
    )

    hive_ms_loader.hive_metastore_service.create_database(database_name)
    hive_ms_loader.sync_metastore(
        database_name=database_name,
        table_name=table_name,
        database_location=database_location,
        table_schema=columns,
        partition_keys=partition_keys,
        format_info=storage_description,
        source_schema=columns,
    )

    # logs were not being register in parallel with logger, thus using print
    print(
        f"m={JOB_NAME}, database_name={database_name}, table_name={table_name}, "
        f"columns={columns}, partition_keys={partition_keys}, "
        f"msg=Completed table schema and partition keys update"
    )


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
    parser = ArgumentParser(JOB_NAME)
    parser.add_argument("bucket", type=str)
    parser.add_argument("layer", type=str)
    parser.add_argument("schema", type=str)
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
        dest="all_tables_flag",
        required=False,
        default=False,
        const=True,
        help="flag to sync all tables from database",
    )

    args = parser.parse_args()
    bucket = args.bucket
    layer = LayerEnum(args.layer).value
    schema = args.schema
    table_name = args.table_name
    all_tables_flag = args.all_tables_flag
    source = "ebdb"

    config_service = ConfigurationService(source)
    table_block_list = [table_name.lower() for table_name in config_service.get_config("table_block_list")]

    driver_logger.info(
        f"m={JOB_NAME}, bucket={bucket}, layer={layer}, schema={schema}, "
        f"table_name={table_name}, all_tables_flag={all_tables_flag}, "
        "msg=Job execution started."
    )

    spark_ms = SparkMetastoreHelper(bucket, layer, schema, table_name, all_tables_flag)
    spark_ms.validate_table_arguments()

    tables_metadata = spark_ms.get_all_tables_metadata()
    tables_metadata = {
        k: v for k, v in tables_metadata.items() if k.lower() not in table_block_list
    }

    hive_ms_host = get_hive_metastore_host()
    hive_ms_client = HiveMetastoreClient(hive_ms_host)
    hive_ms_service = HiveMetastoreService(hive_ms_client)
    hive_ms_loader = HiveMetastoreLoader(hive_ms_service)
    storage_description = TableStorageDescriptorEnum.from_layer(layer)

    func = partial(
        update_table_structure,
        hive_ms_loader,
        spark_ms.spark_database_name,
        spark_ms.database_location,
        storage_description,
    )

    rdd = BaseSparkContext.sc.parallelize(tables_metadata.keys())
    rdd.foreach(
        lambda table_name: func(
            table_name,
            tables_metadata[table_name]["columns"],
            tables_metadata[table_name]["partition_keys"],
        )
    )

    driver_logger.info(f"m={JOB_NAME}, msg=Finished synchronization.")
