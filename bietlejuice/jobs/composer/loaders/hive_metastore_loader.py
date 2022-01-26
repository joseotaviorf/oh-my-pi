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

    def sync_metastore(
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
        Updates the table schema and partition keys in the Hive Metastore based in Spark Metastore values sent via
         arguments.

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
        source_table_partition_keys = partition_keys or []
        table_s3_path = database_location + table_name

        if self._is_table_in_metastore(database_name, table_name):
            schema_changes = self._get_table_schema_changes(
                database_name, table_name, source_schema
            )
            has_partition_keys_changed = not self._partition_keys_match(
                database_name, table_name, source_table_partition_keys
            )
            if schema_changes or has_partition_keys_changed:
                logger.info(
                    f"m=sync_metastore, db={database_name}, table={table_name}, "
                    "msg=Table already exists in metastore. Syncing with spark metastore."
                )
                self.update_table(
                    database_name,
                    table_name,
                    table_s3_path,
                    table_schema,
                    partition_keys,
                    format_info,
                    schema_changes,
                )
            else:
                logger.info(
                    f"m=sync_metastore, db={database_name}, table={table_name}, "
                    "msg=Tables are already synced in both metastores"
                )
        else:
            logger.info(
                f"m=sync_metastore, db={database_name}, table={table_name}, "
                "msg=Table does not exist in metastore. Syncing with spark metastore."
            )
            self.create_table(
                database_name,
                table_name,
                table_s3_path,
                table_schema,
                partition_keys,
                format_info,
            )

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

    def update_table(
        self,
        database_name,
        table_name,
        table_location,
        table_schema,
        source_partition_keys,
        format_info,
        schema_changes,
    ):
        """
        Updates the table in the Hive Metastore.
        If the table is not partitioned, then the table's schema is updated.
        If the table is partitioned or a partition key is modified, then the table needs to be recreated.

        :param database_name: database name
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        :param table_location: specifies the location of the underlying data in
         S3 from which the table is created, for example, 's3://mystorage/'
        :type table_location: str
        :param table_schema: an ordered dict containing the columns name and
         type (including partitioning columns).
        :type table_schema: collections.OrderedDict
        :param source_partition_keys: a list of tuples containing respectively the
        columns name and type for the partition keys. A table can have one or
        more partitions keys. A separate data directory is created for each
        specified combination, which can improve query performance in some
        circumstances. Partitioned columns don't exist within the table data
        itself.
        :type source_partition_keys: List[(string, string)]
        :param format_info: one of TableStorageDescriptor valid layers format.
        This gives information about the table storage parameters.
        :type format_info: bietlejuice.jobs.composer.base.hive.TableFormatInfo
        :param schema_changes: The table added and removed columns
        :type schema_changes: Dict[str, List]

        """
        if source_partition_keys or self._is_table_partitioned(
            database_name, table_name
        ):
            # It is necessary to recreate the table if it is partitioned in some of metastores
            logger.info(
                f"m=update_table, db={database_name}, table={table_name}, msg=The table is partitioned, recreating "
                "instead of update"
            )
            logger.info(
                f"m=update_table, db={database_name}, table={table_name}, msg=Dropping table from Hive Metastore"
            )
            self.hive_metastore_service.drop_table(database_name, table_name)

            logger.info(
                f"m=update_table, db={database_name}, table={table_name}, msg=Recreating table in Metastore"
            )
            self.hive_metastore_service.create_external_table(
                database_name,
                table_name,
                table_location,
                table_schema,
                source_partition_keys,
                format_info,
            )
        else:
            logger.info(
                f"m=update_table, db={database_name}, table={table_name}, msg=Updating non-partitioned table"
            )
            self._update_table_in_metastore(database_name, table_name, schema_changes)

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

        logger.info(
            f"m=update_table_partitions, db={database_name}, table={table_name}, "
            f"msg=Checking table partition values."
        )

        metastore_part_values = self.hive_metastore_service.get_partition_values(
            database_name, table_name
        )
        new_partitions, dropped_partitions = self._map_partition_values_difference(
            database_name, table_name, partition_values, metastore_part_values
        )

        logger.info(
            f"m=update_table_partitions, db={database_name}, table={table_name},"
            f" partitions_to_add={len(new_partitions)} partitions, partitions_to_drop={len(dropped_partitions)} partitions"
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

    def _get_table_schema_changes(self, database_name, table_name, source_schema):
        """
        Returns the table new columns and the removed columns in Spark Metastore.

        :param database_name: the database name
        :type: str
        :param table_name: the table name
        :type: str
        :param source_schema: the table schema in Spark Metastore
        :rtype: Dict[str, List]
        :return: added and removed columns
        """
        hive_table_columns = self.hive_metastore_service.get_table_columns(
            database_name, table_name, ignore_partition_keys=True
        )

        added_columns, removed_columns = self._get_tables_difference(
            source_schema, hive_table_columns
        )

        changes = {}
        if added_columns or removed_columns:
            changes["added_columns"] = added_columns
            changes["removed_columns"] = removed_columns

        return changes

    def _is_table_in_metastore(self, database_name, table_name):
        """
        Checks whether table exists in Hive Metastore.

        :param database_name: the database name
        :type: str
        :param table_name: the table name
        :type: str
        :rtype: boolean
        """
        return table_name in self.hive_metastore_service.get_table_names(database_name)

    def _is_table_partitioned(self, database_name, table_name):
        """
        Checks if table is partitioned in Hive Metastore.

        :param database_name: the database name
        :type: str
        :param table_name: the table name
        :rtype: bool
        """
        return self.hive_metastore_service.get_partition_keys(database_name, table_name)

    def _update_table_in_metastore(self, database_name, table_name, schema_changes):
        """
        Perform an alterantive alter table in the Hive Metastore's table via add and drop commands.

        :param database_name: the database name
        :type: str
        :param table_name: the table name
        :type: str
        :param schema_changes: The table added and removed columns
        :type schema_changes: Dict[str, List]
        :return:
        """
        logger.info(
            f"m=_update_table_in_metastore, db={database_name}, table={table_name}, "
            "msg=Comparing table columns."
        )

        if schema_changes.get("removed_columns"):
            logger.info(
                f"m=_update_table_in_metastore, db={database_name}, table={table_name}, "
                f"removed_columns={schema_changes.get('removed_columns')}, msg=Dropping columns."
            )
            self.hive_metastore_service.drop_columns_from_table(
                database_name, table_name, schema_changes.get("removed_columns")
            )
        if schema_changes.get("added_columns"):
            logger.info(
                f"m=_update_table_in_metastore, db={database_name}, table={table_name}, "
                f"added_columns={[col.name for col in schema_changes.get('added_columns')]}, msg=Adding columns."
            )
            self.hive_metastore_service.add_columns_to_table(
                database_name, table_name, schema_changes.get("added_columns")
            )

    @staticmethod
    def _map_partition_values_difference(
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

    def _partition_keys_match(
        self, database_name, table_name, source_table_partition_keys
    ):
        """
        Verifies if table's partition keys of Spark Metastore and Hive Metastore match.

        :param database_name: the metastore database name
        :type database_name: str
        :param table_name: the metastore table name
        :type table_name: str
        :param source_table_partition_keys: a list of tuples containing respectively the
        columns name and type for the Spark metastore table partition keys.
        :type source_table_partition_keys: List[Tuple(string, string)]
        :rtype: Boolean
        :return: whether exists a difference in the table partition keys
        """
        hive_table_partition_keys = self.hive_metastore_service.get_partition_keys(
            database_name, table_name
        )

        are_partition_keys_matching = (
            source_table_partition_keys == hive_table_partition_keys
        )

        logger.info(
            f"m=partition_keys_match, db={database_name}, table={table_name}, partition_keys_match={are_partition_keys_matching}, "
            "msg=Comparing table partition keys in Spark Metastore with Hive Metastore"
        )
        return are_partition_keys_matching
