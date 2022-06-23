"""
    Synchronizes the (in-house) metastore table based on the Databricks metastore's one.

    It will:
        - sync the partition values (drop or create partitions)
"""
import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.base.spark import BaseSparkContext
from bietlejuice.jobs.composer.base.spark.spark_metastore_helper import (
    SparkMetastoreHelper,
)
from bietlejuice.jobs.composer.metastore_pipeline import (
    SyncMetastoreExternalTablePartitionsPipeline,
)

JOB_NAME = "sync_metastore_tables_partitions"

logging.getLogger("py4j").setLevel(logging.ERROR)


class HiveMetastoreSynchronization:
    def __init__(self, hms_host, layer, spark_database_name) -> None:
        self.hms_host = hms_host
        self.layer = layer
        self.spark_database_name = spark_database_name

    def sync_table_partitions(self, table_spark_metadata):
        """
        Main sync method.
        """

        QuintoAndarLogger(JOB_NAME).info(
            f"m={JOB_NAME}, layer={self.layer}, database_name={self.spark_database_name}, "
            f"table_name={table_spark_metadata['name']}, msg=Starting table partitions synchronization."
        )

        SyncMetastoreExternalTablePartitionsPipeline(
            metastore_host=self.hms_host,
            database_name=self.spark_database_name,
            table_name=table_spark_metadata["name"],
            partition_keys=table_spark_metadata["partition_keys"],
            partition_values=table_spark_metadata["partition_values"],
        ).run()

        QuintoAndarLogger(JOB_NAME).info(
            f"m={JOB_NAME}, layer={self.layer}, database_name={self.spark_database_name}, "
            f"table_name={table_spark_metadata['name']}, msg=Completed table partitions synchronization"
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


def parse_args():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("bucket", type=str, help="Data Lake or DW bucket")
    parser.add_argument("layer_value", type=str, help="One of LayerEnum values")
    parser.add_argument(
        "db_name_part",
        type=str,
        help="The `source` name for raw and clean layers. The `source` and/or "
        "`context` name for enrich layer. The `schema` for DW layer.",
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

    args = parser.parse_args()
    _bucket = args.bucket
    _layer_value = args.layer_value
    _db_name_part = args.db_name_part
    _table_name = args.table_name
    _all_tables = args.all_tables

    return _bucket, _layer_value, _db_name_part, _table_name, _all_tables


if __name__ == "__main__":
    _bucket, _layer_value, _db_name_part, _table_name, _all_tables = parse_args()
    _layer = LayerEnum(_layer_value).value

    QuintoAndarLogger(JOB_NAME).info(
        f"m={JOB_NAME}, bucket={_bucket}, "
        f"layer={_layer}, db_name_part={_db_name_part}, "
        f"table_name={_table_name}, all_tables={_all_tables}, msg=Job execution started."
    )

    spark_ms = SparkMetastoreHelper(
        _bucket, _layer, _db_name_part, _table_name, _all_tables
    )
    spark_ms.validate_table_arguments()

    tables_metadata = spark_ms.get_all_tables_metadata(get_partition_values=True)
    spark_table_names = list(tables_metadata.keys())

    _hms_host = get_hive_metastore_host()
    hms_sync = HiveMetastoreSynchronization(
        _hms_host, _layer, spark_ms.spark_database_name
    )

    rdd = BaseSparkContext.sc.parallelize(spark_table_names)
    rdd.foreach(
        lambda _table_name: hms_sync.sync_table_partitions(
            tables_metadata.get(_table_name)
        )
    )

    QuintoAndarLogger(JOB_NAME).info(f"m={JOB_NAME}, msg=Finished synchronization.")
