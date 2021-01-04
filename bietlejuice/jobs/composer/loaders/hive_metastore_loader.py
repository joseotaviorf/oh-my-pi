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
            database_name, table_name
        )

        added_columns, removed_columns = self._get_tables_difference(
            source_schema, hive_table_columns
        )

        return added_columns, removed_columns

    def create_table(
        self,
        database_name,
        table_name,
        s3_path,
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
        :param s3_path: s3 files path where the table data is located.
         E.g: s3://some/path/
        :type s3_path: str
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
            s3_path,
            table_schema,
            partition_keys,
            format_info,
        )
        # TODO: if partitions: implement "our" msck

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

        if self._is_table_in_metastore(database_name, table_name):
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
    def _get_tables_difference(table_source, metastore_columns):
        """
        Identifies the columns that were added and removed from the table source.

        :param table_source: the most updated columns list from table source
        :type table_source: collections.OrderedDict
        :param metastore_columns: the columns list from table's data lake metastore
        :type metastore_columns: Dict[str, str]
        :return: a list with new columns and another list with the removed ones
        :rtype: List[FieldSchema], List[str]
        """
        metastore_columns_names = list(metastore_columns.keys())
        removed_columns = metastore_columns_names
        added_columns = []
        for col_name, col_type in table_source.items():
            if (
                col_name in metastore_columns_names
                and col_type == metastore_columns[col_name]
            ):
                removed_columns.remove(col_name)
            else:
                added_columns.append(ColumnBuilder(col_name, col_type).build())

        return added_columns, removed_columns

    def _is_table_in_metastore(self, database_name, table_name):
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

    def add_partitions_to_table(self, database_name, table_name, partition_values_list):
        """
        Add partitions value as new partitions to Hive table.

        :param database_name: the database name
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :param partition_values_list: values as a list, in the correct order, to be added as a new partition to the table
        :type partition_values_list: List[List[str]]
        :return: None
        """
        partition_list = []

        for partition in partition_values_list:
            partition_list.append(
                PartitionBuilder(
                    values=partition, db_name=database_name, table_name=table_name
                ).build()
            )

        if partition_list:
            self.hive_metastore_service.add_partitions_to_table(
                database_name, table_name, partition_list
            )

            logger.info(
                f"m=add_partitions_to_table, db={database_name}, table={table_name}, "
                "msg=Successfully added partitions to table."
            )
        else:
            raise ValueError(
                f"m=add_partitions_to_table, db={database_name}, table={table_name}, "
                f"partitions={partition_list}, "
                "msg=Partitions must be informed."
            )
