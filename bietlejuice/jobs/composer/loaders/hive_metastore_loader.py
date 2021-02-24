from hive_metastore_client.builders import ColumnBuilder
from hive_metastore_client.builders import PartitionBuilder

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("HiveMetastoreLoader")


class HiveMetastoreLoader:
    """Loads Spark DataFrame schemas into Hive Metastore as a table."""

    def __init__(self, metastore_service):
        """
        Constructor.

        :param metastore_service: service to interact with the Hive Metastore
        :type metastore_service: HiveMetastoreService
        """
        self.hive_metastore_service = metastore_service

    def compare_table_schema(self, database_name, table_name, source_schema):
        """
        Compare the table schema from Spark Metastore (in Databricks) with Hive
         Metastore.

        :param database_name: the database name of the table
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :param source_schema: columns to compare the table schema with
        :type source_schema: collections.OrderedDict
        :return: a list with new columns and another list with the removed ones
        :rtype: List[FieldSchema], List[str]
        """
        hive_table_columns = self.hive_metastore_service.get_table_columns(
            database_name, table_name, ignore_partition_keys=True
        )

        added_columns, removed_columns = self._get_tables_difference(
            source_schema, hive_table_columns
        )

        return added_columns, removed_columns

    def create_table(
        self,
        database_name,
        table_name,
        table_location,
        table_schema,
        partition_keys,
        format_info,
    ):
        """
        Create a new table in the Hive Metastore.

        :param database_name: the database name
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :param table_location: s3 path where the table files data are located.
         E.g: s3://some/path/
        :type table_location: str
        :param table_schema: an ordered dict containing the columns name and
         type (including partitioning columns).
        :type table_schema: collections.OrderedDict
        :param partition_keys: an ordered dict containing respectively the
        columns name and type for the partition keys. A table can have one or
        more partitions keys. A separate data directory is created for each
        specified combination, which can improve query performance in some
        circumstances. Partitioned columns don't exist within the table data
        itself.
        :type partition_keys: collections.OrderedDict
        :param format_info: one of TableStorageDescriptor valid layers format.
         This gives information about the table storage parameters.
         E.g. TableStorageDescriptorEnum.RAW_FORMAT
        :type format_info: bietlejuice.jobs.composer.base.hive.TableFormatInfo
        """
        logger.info(
            f"m=create_table, db={database_name}, table={table_name}, msg=Creating table."
        )
        partition_keys = partition_keys or {}

        self.hive_metastore_service.create_external_table(
            database_name,
            table_name,
            table_location,
            table_schema,
            partition_keys,
            format_info,
        )

    def update_metastore(
        self,
        database_name,
        table_name,
        database_location,
        table_schema,
        partition_keys,
        format_info,
        source_schema,
    ):
        """

        :param database_name: the database name
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :param database_location: s3 path where the database is located.
         E.g: s3://some/path/
        :type database_location: str
        :param table_schema: an ordered dict containing the columns name and
         type (including partitioning columns).
        :type table_schema: collections.OrderedDict
        :param partition_keys: a list of tuples containing respectively the
        columns name and type for the partition keys. A table can have one or
        more partitions keys. A separate data directory is created for each
        specified combination, which can improve query performance in some
        circumstances. Partitioned columns don't exist within the table data
        itself.
        :type partition_keys: List[Tuple(string, string)]
        :param format_info: one of TableStorageDescriptor valid layers format.
         This gives information about the table storage parameters.
         E.g. TableStorageDescriptor.RAW_FORMAT
        :type format_info: bietlejuice.jobs.composer.base.hive.TableFormatInfo
        :param source_schema: columns to compare the table schema with
        :type source_schema: collections.OrderedDict
        """
        partition_keys = partition_keys or []
        table_s3_path = database_location + table_name

        if self.is_table_in_metastore(database_name, table_name):
            self._check_partition_keys(database_name, table_name, partition_keys)
            self._update_table_in_metastore(database_name, table_name, source_schema)
        else:
            self.create_table(
                database_name,
                table_name,
                table_s3_path,
                table_schema,
                partition_keys,
                format_info,
            )

        logger.info(
            f"m=update_metastore, db={database_name}, table={table_name}, "
            "msg=Successfully loaded table in metastore."
        )

    @staticmethod
    def _get_tables_difference(spark_table_columns, metastore_table_columns):
        """
        Identifies the columns that were added and removed from the table in Spark Metastore.

        :param spark_table_columns: the most updated columns list from table in Spark Metastore
        :type spark_table_columns: collections.OrderedDict
        :param metastore_table_columns: the columns list from table's data lake metastore
        :type metastore_table_columns: Dict[str, str]
        :return: a list with new columns and another list with the removed ones
        :rtype: List[FieldSchema], List[str]
        """
        metastore_columns_names = list(metastore_table_columns.keys())
        removed_columns = metastore_columns_names
        added_columns = []
        for col_name, col_type in spark_table_columns.items():
            if (
                col_name in metastore_columns_names
                and col_type == metastore_table_columns[col_name]
            ):
                removed_columns.remove(col_name)
            else:
                added_columns.append(ColumnBuilder(col_name, col_type).build())

        return added_columns, removed_columns

    def is_table_in_metastore(self, database_name, table_name):
        """
        Checks whether table exists in Hive Metastore.

        :param database_name:
        :param table_name:
        :rtype: boolean
        """
        return table_name in self.hive_metastore_service.get_table_names(database_name)

    def _update_table_in_metastore(self, database_name, table_name, source_schema):
        logger.info(
            f"m=_update_table_in_metastore, db={database_name}, table={table_name}, "
            "msg=Table already exists in metastore. Syncing with spark metastore."
        )
        added_columns, removed_columns = self.compare_table_schema(
            database_name, table_name, source_schema
        )
        if removed_columns:
            logger.info(
                f"m=_update_table_in_metastore, db={database_name}, table={table_name}, "
                f"removed_columns={removed_columns}, msg=Dropping columns."
            )
            self.hive_metastore_service.drop_columns_from_table(
                database_name, table_name, removed_columns
            )
        if added_columns:
            logger.info(
                f"m=_update_table_in_metastore, db={database_name}, table={table_name}, "
                f"added_columns={[col.name for col in added_columns]}, msg=Adding columns."
            )
            self.hive_metastore_service.add_columns_to_table(
                database_name, table_name, added_columns
            )

    def update_table_partitions(self, database_name, table_name, partition_values):
        """
        Updates partitions values of Hive table.

        Compares the partitions values of the metastore table against the given
         partitions list and performs one of the operations below based in
         the delta:
          - Adds new partitions in Hive table
          - Drops the partitions from metastore table

        :param database_name: the database name
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :param partition_values: partition values as a list, in the correct order,
         to be added as a new partition to the table
        :type partition_values: List[List[str]]
        """

        metastore_part_values = self.hive_metastore_service.get_partition_values(
            database_name, table_name
        )
        new_partitions, dropped_partitions = self._get_partitions_difference(
            database_name, table_name, partition_values, metastore_part_values
        )

        if dropped_partitions:
            logger.info(
                f"m=update_table_partitions, db={database_name}, table={table_name}, "
                f"dropped_partitions={dropped_partitions}, msg=Dropping partitions in Hive Metastore Table."
            )
            self.hive_metastore_service.drop_partitions_from_table(
                database_name, table_name, dropped_partitions
            )
        if new_partitions:
            logger.info(
                f"m=update_table_partitions, db={database_name}, table={table_name}, "
                f"new_partitions={new_partitions}, msg=Adding partitions in Hive Metastore table."
            )
            self.hive_metastore_service.add_partitions_to_table(
                database_name, table_name, new_partitions
            )

    @staticmethod
    def _get_partitions_difference(
        database_name, table_name, spark_partition_values, metastore_partition_values
    ):
        """
        Identifies the partitions that were added and removed from the table in Spark Metastore.

        :param spark_partition_values: the most updated partitions values list from table in Spark Metastore
        :type spark_partition_values: List[List[str]]
        :param metastore_partition_values: the partitions values list from table's data lake metastore
        :type metastore_partition_values: List[List[str]]
        :return: a list with new partitions and another list with the removed ones
        :rtype: List[str], List[str]
        """
        removed_partitions = metastore_partition_values[:]
        added_partitions = []
        for partition_values in spark_partition_values:
            if partition_values in metastore_partition_values:
                removed_partitions.remove(partition_values)
            else:
                added_partitions.append(
                    PartitionBuilder(
                        values=partition_values,
                        db_name=database_name,
                        table_name=table_name,
                    ).build()
                )

        return added_partitions, removed_partitions

    def add_partitions_to_table(self, database_name, table_name, partition_values_list):
        """
        Add partitions values as new partitions to Hive table.

        :param database_name: the database name
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :param partition_values_list: values as a list, in the correct order,
         to be added as a new partition to the table
        :type partition_values_list: List[List[str]]
        :raises: ValueError
        """
        if not partition_values_list:
            raise ValueError(
                f"m=add_partitions_to_table, db={database_name}, table={table_name}, "
                f"partition_values_list={partition_values_list}, "
                "msg=No partitions informed."
            )

        partition_list = []
        for partition in partition_values_list:
            partition_list.append(
                PartitionBuilder(
                    values=partition, db_name=database_name, table_name=table_name
                ).build()
            )

        self.hive_metastore_service.add_partitions_to_table(
            database_name, table_name, partition_list
        )

        logger.info(
            f"m=add_partitions_to_table, db={database_name}, table={table_name}, "
            f"partition_values_list={partition_values_list} msg=Successfully added partitions to table."
        )

    def _check_partition_keys(
        self, database_name, table_name, source_table_partition_keys
    ):
        """
        Verifies if partition keys of Spark Metastore and Hive Metastore tables match.

        Throws an error if partitions differs.

        :param database_name: the metastore database name
        :type database_name: str
        :param table_name: the metastore table name
        :type table_name: str
        :param source_table_partition_keys: a list of tuples containing respectively the
        columns name and type for the Spark metastore table partition keys.
        :type source_table_partition_keys: List[Tuple(string, string)]
        :rtype: None
        :raises: ValueError
        """
        hive_table_partition_keys = self.hive_metastore_service.get_partition_keys_names(
            database_name, table_name
        )

        if hive_table_partition_keys != source_table_partition_keys:
            raise ValueError(
                f"m=_check_partition_keys, spark_partitions={source_table_partition_keys},"
                f" hive_partition_keys={hive_table_partition_keys}, msg=Partitions in Spark and Hive metastores are "
                "not matching. You should recreate the table in Spark metastore if you are trying to change the "
                "partition keys of the table."
            )
