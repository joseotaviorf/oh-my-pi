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
from collections import OrderedDict

from pyspark.sql.functions import split
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreMapping
from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.db.dw_metastore_mapping import DwMetastoreMapping
from bietlejuice.jobs.composer.base.hive import TableStorageDescriptorEnum
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers.databricks_consumer import (
    DatabricksConsumer,
)
from bietlejuice.jobs.composer.pipeline import MetastoreExternalTablePipeline
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseSparkContext

JOB_NAME = "sync_metastore_tables"

logging.getLogger("py4j").setLevel(logging.ERROR)


class SparkMetastoreHelper:
    def __init__(self, bucket, layer, db_name_part, table_name, all_tables) -> None:
        self.bucket = bucket
        self.layer = layer
        self.db_name_part = db_name_part
        self.table_name = table_name
        self.all_tables = all_tables
        self.spark_database_name, self.database_location = (
            self.get_metastores_metadata()
        )
        self.spark_metastore_service = SparkMetastoreService(SparkClient())

    def get_metastores_metadata(self):
        """
        Gets the Spark and Hive metastores databases metadata for specified layer.

        :return: the spark database name and the database location
        """
        if self.layer == LayerEnum.DW.value:
            dw_ms_mapping = DwMetastoreMapping(
                schema=self.db_name_part, bucket=self.bucket
            ).get_all_dw_info()

            spark_database_name = dw_ms_mapping["dw_schema_databricks"]
            database_location = dw_ms_mapping["dw_schema_path"]
        else:
            dl_ms_mapping = DatalakeMetastoreMapping(
                source=self.db_name_part, bucket=self.bucket
            )

            (
                spark_database_name,
                database_location,
            ) = dl_ms_mapping.get_datalake_info_from_layer(self.layer)

        return spark_database_name, database_location

    def validate_table_arguments(self):
        """
        Verifies if the job is called exclusively for syncing a unique table or
         all of them.

        :raises: ValueError
        """
        if bool(self.table_name) == self.all_tables:
            raise ValueError(
                f"m={JOB_NAME}, table_name={self.table_name},"
                f"all_tables={self.all_tables}, msg=Parameters table_name and all_tables are mutual exclusive."
            )

    @staticmethod
    def set_columns_to_lower(table_schema):
        """
        Normalizes the Spark columns to lower case because the Spark metastore
         saves the columns camel-cased (for raw tables) and the Hive metastore
         saves it lower-cased.

        :param table_schema: schema with columns and types
        :type table_schema: collections.OrderedDict[(string, string)]
        :return: dictionary with table columns names (lowered) and types in tuples
        :rtype: collections.OrderedDict[(string, string)]
        """
        cleaned_schema = [(_col.lower(), _type) for _col, _type in table_schema.items()]
        return OrderedDict(cleaned_schema)

    @staticmethod
    def set_timestamps_as_string(spark_ms_table_columns):
        """
        Forcefully set the timestamp columns to string.

        Some json data in Spark Metastore raw tables are automatically interpreted
         as timestamp and the date part is automatically extracted when we select data.
         For example, for the raw data {"revision_date":"{\"$date\": \"2021-01-10T00:00:00.157Z\"}"}
         the command `select revision_date from table_a` will return `2021-01-10T00:00:00.157Z`
         instead of the full json content with the key `$date`.
        The Hive Metastore does not automatically extracts the date part for the timestamp columns,
          but raises a parse error instead.

        :param spark_ms_table_columns: the spark columns schema
        :return: columns with timestamps as string
        :rtype: collections.OrderedDict[(string, string)]
        """
        for col in spark_ms_table_columns:
            spark_ms_table_columns[col] = spark_ms_table_columns[col].replace(
                "timestamp", "string"
            )

        return spark_ms_table_columns

    @staticmethod
    def format_df_partition_values(df_partition_values):
        """
        Converts the df with existing partition values from Databricks Metastore to
         a list with lists of partition values.

        :param df_partition_values: spark dataframe returned from SHOW PARTITIONS command
        :type df_partition_values: pyspark.sql.DataFrame
        :rtype: List[List[str]]
        """
        if not df_partition_values or "partition" not in df_partition_values.columns:
            QuintoAndarLogger(JOB_NAME).info(
                f"m={JOB_NAME}, msg=No partition found in table's dataframe"
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

    def get_spark_metastore_table_partition_values(self, table_name):
        """
        Query the Spark metastore to get all the partitions values for given table.

        :param table_name: table from which partitions will be fetched
        :return: List[List[str]]
        """
        databricks_consumer = DatabricksConsumer(
            {"db": self.spark_database_name}, SparkClient()
        )
        databricks_partition_values = databricks_consumer.get_partition_values_from_table(
            table_name=table_name
        )
        formatted_partition_values = self.format_df_partition_values(
            df_partition_values=databricks_partition_values
        )
        return formatted_partition_values

    def is_raw_sync(self):
        return LayerEnum.RAW.value in self.spark_database_name

    def get_spark_metastore_table_columns(self, table):
        """
        Fetches the table columns names and types in Spark metastore.

        :param table: target table
        :return: dictionary with table columns names (lowered) and types in tuples
        :rtype: collections.OrderedDict[(string, string)]
        """
        spark_ms_table_columns = self.spark_metastore_service.get_table_schema(
            self.spark_database_name, table, ignore_partition_keys=True
        )

        if self.is_raw_sync():
            spark_ms_table_columns = self.set_timestamps_as_string(
                spark_ms_table_columns
            )

        return self.set_columns_to_lower(spark_ms_table_columns)

    def get_table_names(self):
        """
        Returns the table names to be synced according to the job arguments
        :rtype: list
        """
        table_names = []
        if self.all_tables:
            table_names = self.get_spark_metastore_table_names()
        else:
            table_names.append(self.table_name)

        return table_names

    def get_spark_metastore_table_names(self):
        """
        Query the Spark metastore to get all the table names for given database.

        :return: List[str]
        """
        databricks_consumer = DatabricksConsumer(
            {"db": self.spark_database_name}, SparkClient()
        )
        df_databricks_tables = databricks_consumer.get_table_names_and_sizes()
        return [row.table_name for row in df_databricks_tables.collect()]

    def get_all_tables_metadata(self):
        """
        Fetches all database tables metadata.
        This metadata will be shared during the parallelized processing of table names RDD.

        :return: table schema and partition information
        :rtype: dict
        """
        tables_spark_metadata = dict()
        for table_name in self.get_table_names():
            spark_ms_table_columns = self.get_spark_metastore_table_columns(table_name)
            spark_ms_table_partition_keys = self.spark_metastore_service.get_table_partition_keys(
                self.spark_database_name, table_name
            )

            spark_ms_table_partition_values = []
            if spark_ms_table_partition_keys:
                spark_ms_table_partition_values = self.get_spark_metastore_table_partition_values(
                    table_name
                )

            tables_spark_metadata[table_name] = dict()
            tables_spark_metadata[table_name]["name"] = table_name
            tables_spark_metadata[table_name]["columns"] = spark_ms_table_columns
            tables_spark_metadata[table_name][
                "partition_keys"
            ] = spark_ms_table_partition_keys
            tables_spark_metadata[table_name][
                "partition_values"
            ] = spark_ms_table_partition_values
        return tables_spark_metadata


class HiveMetastoreSynchronization:
    def __init__(self, hms_host, layer, spark_database_name, database_location) -> None:
        self.hms_host = hms_host
        self.layer = layer
        self.spark_database_name = spark_database_name
        self.database_location = database_location

    def sync_table(self, table_spark_metadata):
        """
        Main sync method.
        """

        QuintoAndarLogger(JOB_NAME).info(
            f"m={JOB_NAME}, layer={self.layer}, database_name={self.spark_database_name}, "
            f"table_name={table_spark_metadata['name']}, msg=Starting table synchronization."
        )

        MetastoreExternalTablePipeline(
            metastore_host=self.hms_host,
            database_name=self.spark_database_name,
            table_name=table_spark_metadata["name"],
            database_location=self.database_location,
            table_schema=table_spark_metadata["columns"],
            partition_keys=table_spark_metadata["partition_keys"],
            partition_values=table_spark_metadata["partition_values"],
            format_info=TableStorageDescriptorEnum.from_layer(self.layer),
        ).run()

        QuintoAndarLogger(JOB_NAME).info(
            f"m={JOB_NAME}, layer={self.layer}, database_name={self.spark_database_name}, "
            f"table_name={table_spark_metadata['name']}, msg=Table synchronized."
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

    tables_metadata = spark_ms.get_all_tables_metadata()
    spark_table_names = list(tables_metadata.keys())

    _hms_host = get_hive_metastore_host()
    hms_sync = HiveMetastoreSynchronization(
        _hms_host, _layer, spark_ms.spark_database_name, spark_ms.database_location
    )

    rdd = BaseSparkContext.sc.parallelize(spark_table_names)
    rdd.foreach(
        lambda _table_name: hms_sync.sync_table(tables_metadata.get(_table_name))
    )

    QuintoAndarLogger(JOB_NAME).info(f"m={JOB_NAME}, msg=Finished synchronization.")
