from hive_metastore_client.builders import (
    SerDeInfoBuilder,
    StorageDescriptorBuilder,
    TableBuilder,
    ColumnBuilder,
    DatabaseBuilder,
)
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.services.metastore_services.metastore_service import (
    MetastoreService,
)

logger = QuintoAndarLogger("HiveMetastoreService")


class HiveMetastoreService(MetastoreService):
    """Service to interact with our internal Hive Metastore."""

    DEFAULT_TABLE_OWNER = "Data Engineering Team"

    def __init__(self, client):
        """
        Constructor.

        :param client: an instance of hive_metastore_client.HiveMetastoreClient
        """
        self._client = client

    @property
    def client(self):
        """:rtype: hive_metastore_client.HiveMetastoreClient"""
        return self._client

    def create_external_table(
        self,
        database_name,
        table_name,
        table_location,
        table_schema,
        partition_cols,
        format_info,
    ):
        """
        Creates the table in Hive Metastore.

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
        :param partition_cols: a list of tuples containing respectively the
        columns name and type for the partition keys. A table can have one or
        more partitions keys. A separate data directory is created for each
        specified combination, which can improve query performance in some
        circumstances. Partitioned columns don't exist within the table data
        itself.
        :type partition_cols: List[(string, string)]
        :param format_info: one of TableStorageDescriptor valid layers format.
        This gives information about the table storage parameters.
        :type format_info: bietlejuice.jobs.composer.base.hive.TableFormatInfo
        """

        columns = self._build_columns_from_dict(table_schema.items())
        partition_keys = self._build_columns_from_dict(partition_cols)

        serde_info = SerDeInfoBuilder(
            serialization_lib=format_info.serde_lib,
            parameters={"timestamp.formats": "yyyy-MM-dd'T'HH:mm:ss.SSSS'Z'"},
        ).build()

        storage_descriptor = StorageDescriptorBuilder(
            columns=columns,
            location=table_location,
            input_format=format_info.input_format,
            output_format=format_info.output_format,
            serde_info=serde_info,
        ).build()

        table = TableBuilder(
            table_name=table_name,
            db_name=database_name,
            owner=self.DEFAULT_TABLE_OWNER,
            storage_descriptor=storage_descriptor,
            partition_keys=partition_keys,
        ).build()

        with self.client as conn:
            conn.create_external_table(table)

    @staticmethod
    def _build_columns_from_dict(table_columns):
        """
        Transforms given table columns structure in the Hive Metastore Client
        expected object.

        :param table_columns: an list of tuples containing the columns name and
         type (including partitioning columns).
        :type table_columns: List[(string, string)]
        :return: columns list in the structure required by the Hive Metastore client
        :rtype: List[ColumnBuilder]
        """
        columns = []
        for col_name, col_type in table_columns:
            columns.append(ColumnBuilder(col_name, col_type).build())

        return columns

    def create_database(self, database_name):
        """
        Creates the database in the Hive Metastore if it does not exist.

        :param database_name: the new database name
        :type database_name: str
        """
        with self.client as conn:
            database = DatabaseBuilder(database_name).build()
            conn.create_database_if_not_exists(database)

    def repair_table_partitions(self, database_name, table_name):
        raise NotImplementedError(
            "m=repair_table_partitions, msg=method not implemented"
        )

    def drop_table(self, database_name, table_name, delete_data=False):
        """
        Drops the table in the Hive Metastore.

        :param database_name: the database name
        :type: str
        :param table_name: the table name
        :type: str
        :param delete_data: whether the data should be deleted (for managed tables)
        :type: bool
        """
        with self.client as conn:
            return conn.drop_table(database_name, table_name, delete_data)

    def get_table_names(self, database_name, regex="*"):
        """
        Fetches the tables existent in the database.

        :param database_name: the database name
        :param regex: regex filter to apply in the table names
        :return: list with table names
        :rtype: List[str]
        """
        with self.client as conn:
            return conn.get_all_tables(database_name)

    def get_table_description(self, database_name, table_name, formatted=False):
        raise NotImplementedError("m=get_table_description, msg=method not implemented")

    def add_partitions_to_table(self, database_name, table_name, partition_list):
        """
        Add partitions to the Hive table.

        :param database_name: the database name
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :param partition_list: list of partitions to be added to the table
        :type partition_list: List[Partition]
        """
        with self.client as conn:
            conn.add_partitions_if_not_exists(database_name, table_name, partition_list)

    def drop_partitions_from_table(self, database_name, table_name, partition_list):
        """
        Drops the partitions values list from the metastore in bulk.

        :param database_name: the database name
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :param partition_list: partition values
        :type partition_list: List[List[str]]
        """
        with self.client as conn:
            conn.bulk_drop_partitions(database_name, table_name, partition_list)

    def create_new_partitions_from_df(
        self, database_name, table_name, df, partition_cols, parallelism=1
    ):
        raise NotImplementedError(
            "m=create_new_partitions_from_df, msg=method not implemented"
        )

    def get_table(self, database_name, table_name):
        """
        Gets the table object from Hive Metastore.

        :param database_name: database name of the table
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        :return: the table object
        :rtype: thrift_files.libraries.thrift_hive_metastore_client.ttypes.Table
        """
        with self.client as conn:
            return conn.get_table(database_name, table_name)

    def get_table_schema(self, database_name, table_name):
        """
        Gets the table schema from Hive Metastore.

        :param database_name: database name of the table
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        :return: a list with the table columns
        :rtype: List[FieldSchema]
        """
        with self.client as conn:
            return conn.get_schema(database_name, table_name)

    def get_table_columns(self, database_name, table_name, ignore_partition_keys=False):
        """
        Fetches the table columns list from Hive Metastore.

        :param database_name: the database name of the table
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :param ignore_partition_keys: indicates if the partition keys should be
         removed from the result set
        :type ignore_partition_keys: bool
        :return: dictionary of columns types
        :rtype: Dict[str,str]
        """
        table = self.get_table(database_name, table_name)
        table_cols = self._parse_field_schema(table.sd.cols)
        if ignore_partition_keys:
            partition_keys = self._parse_field_schema(table.partitionKeys)
            table_cols = set(table_cols.items()).difference(set(partition_keys.items()))

        return dict(table_cols)

    @staticmethod
    def _parse_field_schema(table_schema):
        """
        Turn FieldSchema list into a dictionary.

        :param table_schema: the list of columns
        :type table_schema: List[FieldSchema]
        :return: dictionary of columns types, where key is the column name and
         value is the column type.
        :rtype: Dict[str,str]
        """
        columns = {}
        for field_schema in table_schema:
            columns[field_schema.name] = field_schema.type

        return columns

    def add_columns_to_table(self, database_name, table_name, columns):
        """
        Add new columns in the metastore table.

        :param database_name: the database name
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :param columns: list with columns objects to be added
        :type columns: List[FieldSchema]
        """
        with self.client as conn:
            conn.add_columns_to_table(database_name, table_name, columns)

    def drop_columns_from_table(self, database_name, table_name, columns):
        """
        Drops the columns in the metastore table.

        :param database_name: the database name
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :param columns: list with columns names to be deleted
        :type columns: List[str]
        """
        with self.client as conn:
            conn.drop_columns_from_table(database_name, table_name, columns)

    def get_partition_keys(self, database_name, table_name):
        """
        Gets the partition keys names and types from Metastore table.

        :param database_name: the database name
        :param table_name: the table name
        :rtype: List[str]
        """
        with self.client as conn:
            return conn.get_partition_keys(database_name, table_name)

    def get_partition_keys_names(self, database_name, table_name):
        """
        Gets the partition keys names from Metastore table.

        :param database_name: the database name
        :param table_name: the table name
        :rtype: List[str]
        """
        with self.client as conn:
            return conn.get_partition_keys_names(database_name, table_name)

    def get_partition_values(self, database_name, table_name):
        """
        Gets the partition values from Metastore table.

        :param database_name: the database name
        :param table_name: the table name
        :rtype: List[List[str]]
        """
        with self.client as conn:
            return conn.get_partition_values_from_table(database_name, table_name)
