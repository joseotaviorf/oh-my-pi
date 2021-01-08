import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum, DataLakeMetastoreMapping
from bietlejuice.jobs.composer.base.hive import TableStorageDescriptorEnum
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.pipeline import MetastoreExternalTablePipeline
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "create_metastore_external_table"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
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

    # TODO DF-326: receive partition values

    args = parser.parse_args()
    env = args.env
    data_lake_bucket = args.datalake_bucket
    layer = args.layer
    database_base_name = args.database_base_name
    table_name = args.table_name
    partition_keys = args.partition_keys.split(",")

    logger.info(
        f"m={JOB_NAME}, env={env}, datalake_bucket={data_lake_bucket}, "
        + f"layer={layer}, database_base_name={database_base_name}, table_name={table_name}, msg=Job execution started."
    )

    dlmp = DataLakeMetastoreMapping(env, database_base_name, data_lake_bucket)
    (
        databricks_database_name,
        database_location,
        metastore_database_name,
    ) = dlmp.get_data_lake_info_from_layer(layer)

    spark_metastore_service = SparkMetastoreService(SparkClient())
    spark_table_schema = spark_metastore_service.get_table_schema(
        databricks_database_name, table_name
    )
    storage_descriptor_info = TableStorageDescriptorEnum.from_layer(layer)

    hm_confs = dbutils.secrets.get(  # noqa: F821
        "quintoandar", DatabaseEnum.HIVE_METASTORE
    )
    hm_confs_json = json.loads(hm_confs)

    MetastoreExternalTablePipeline(
        metastore_host=hm_confs_json["host"],
        database_name=metastore_database_name,
        table_name=table_name,
        database_location=database_location,
        table_schema=spark_table_schema,
        partition_keys=partition_keys,
        format_info=storage_descriptor_info,
    ).run()
