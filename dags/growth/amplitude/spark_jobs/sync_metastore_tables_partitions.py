import json
import logging
from argparse import ArgumentParser
from functools import partial

from hive_metastore_client import HiveMetastoreClient
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db.database_enum import DatabaseEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.spark.base_spark import BaseSparkContext
from bietlejuice.base.spark.spark_metastore_helper import SparkMetastoreHelper
from bietlejuice.loaders.hive_metastore_loader import HiveMetastoreLoader
from bietlejuice.services.metastore_services.hive_metastore_service import (
    HiveMetastoreService,
)

JOB_NAME = "sync_metastore_tables_partitions"

logging.getLogger("py4j").setLevel(logging.ERROR)
driver_logger = QuintoAndarLogger(JOB_NAME)


def get_hive_metastore_host():
    """
    Retrieves the Hive Metastore host stored in Databricks secrets
    """
    hm_confs = dbutils.secrets.get(  # noqa: F821
        "quintoandar", DatabaseEnum.HIVE_METASTORE
    )
    hm_confs_json = json.loads(hm_confs)
    return hm_confs_json["host"]


def update_table_partitions(
    hive_ms_loader: HiveMetastoreLoader,
    database_name: str,
    table_name: str,
    partition_values: list,
):
    """
    Updates partition values of a single table in Hive Metastore, dropping or creating
    them according to the values provided. Used for multiple concurrent requests that
    share the same Hive Metastore Loader object.
    Args:
        hive_ms_loader (HiveMetastoreLoader): Hive Metastore Loader object
        database_name (str): Name of the database from Databricks Metastore that
            contains the table(s) which partitions will be updated in Hive Metastore.
        table_name (str): Name of the table which partitions will be updated in Hive
            Metastore.
        partition_values (List[List[str]]): List of lists with partition values as
            strings.
    """
    # logs were not being register in parallel with logger, thus using print
    print(
        f"m={JOB_NAME}, database_name={database_name}, table_name={table_name}, "
        f"partition_values={partition_values}, msg=Starting table partition values update"
    )

    hive_ms_loader.update_table_partitions(
        database_name=database_name,
        table_name=table_name,
        partition_values=partition_values,
    )

    # logs were not being register in parallel with logger, thus using print
    print(
        f"m={JOB_NAME}, database_name={database_name}, table_name={table_name}, "
        f"partition_values={partition_values}, msg=Completed table partition values update"
    )


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

    driver_logger.info(
        f"m={JOB_NAME}, bucket={bucket}, layer={layer}, schema={schema}, "
        f"table_name={table_name}, all_tables_flag={all_tables_flag}, "
        "msg=Job execution started."
    )

    spark_ms = SparkMetastoreHelper(bucket, layer, schema, table_name, all_tables_flag)
    spark_ms.validate_table_arguments()

    tables_metadata = spark_ms.get_all_tables_metadata(get_partition_values=True)
    tables_partition_values = {
        table_name: table_metadata["partition_values"]
        for table_name, table_metadata in tables_metadata.items()
        if table_metadata["partition_keys"]
    }

    hive_ms_host = get_hive_metastore_host()
    hive_ms_client = HiveMetastoreClient(hive_ms_host)
    hive_ms_service = HiveMetastoreService(hive_ms_client)
    hive_ms_loader = HiveMetastoreLoader(hive_ms_service)

    func = partial(
        update_table_partitions, hive_ms_loader, spark_ms.spark_database_name
    )

    rdd = BaseSparkContext.sc.parallelize(tables_partition_values.keys())
    rdd.foreach(
        lambda table_name: func(table_name, tables_partition_values[table_name])
    )

    driver_logger.info(f"m={JOB_NAME}, msg=Finished synchronization.")
