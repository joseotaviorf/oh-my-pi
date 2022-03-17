from collections import OrderedDict

from pyspark.sql.functions import split
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreMapping
from bietlejuice.jobs.composer.base.db.dw_metastore_mapping import DwMetastoreMapping
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers.databricks_consumer import (
    DatabricksConsumer,
)
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

logger = QuintoAndarLogger("SparkMetastoreHelper")


class SparkMetastoreHelper:
    def __init__(self, bucket, layer, db_name_part, table_name, all_tables) -> None:
        self.bucket = bucket
        self.layer = layer
        self.db_name_part = db_name_part
        self.table_name = table_name
        self.all_tables = all_tables
        (
            self.spark_database_name,
            self.database_location,
        ) = self.get_metastores_metadata()
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
                f"m=validate_table_arguments, table_name={self.table_name},"
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
            logger.info(
                f"m=format_df_partition_values, msg=No partition found in table's dataframe"
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

    def get_all_tables_metadata(self, get_partition_values=False):
        """
        Fetches all database tables metadata.
        This metadata will be shared during the parallelized processing of table names RDD.

        :param get_partition_values: whether to get each table partition values or not
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
            if get_partition_values and spark_ms_table_partition_keys:
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
