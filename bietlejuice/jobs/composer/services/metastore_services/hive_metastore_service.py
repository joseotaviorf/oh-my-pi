from hive_metastore_client.builders import (
    SerDeInfoBuilder,
    StorageDescriptorBuilder,
    TableBuilder,
    ColumnBuilder,
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
        :param partition_cols: an ordered dict containing respectively the
        columns name and type for the partition keys. A table can have one or
        more partitions keys. A separate data directory is created for each
        specified combination, which can improve query performance in some
        circumstances. Partitioned columns don't exist within the table data
        itself.
        :type partition_cols: collections.OrderedDict
        :param format_info: one of TableStorageDescriptor valid layers format.
        This gives information about the table storage parameters.
        :type format_info: bietlejuice.jobs.composer.base.hive.TableFormatInfo
        """

        columns = self._build_columns_from_dict(table_schema)
        partition_keys = self._build_columns_from_dict(partition_cols)

        serde_info = SerDeInfoBuilder(serialization_lib=format_info.serde_lib).build()

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
            conn.create_table(table)

    @staticmethod
    def _build_columns_from_dict(table_columns):
        """
        Transforms given table columns structure in the Hive Metastore Client
        expected object.

        :param table_columns: an ordered dict containing the columns name and
         type (including partitioning columns).
        :type table_columns: collections.OrderedDict
        :return: columns list in the structure required by the Hive Metastore client
        :rtype: List[ColumnBuilder]
        """
        columns = []
        for col_name, col_type in table_columns.items():
            columns.append(ColumnBuilder(col_name, col_type).build())

        return columns

    def create_database(self, database_name):
        raise NotImplementedError("m=create_database, msg=method not implemented")

    def repair_table_partitions(self, database_name, table_name):
        raise NotImplementedError(
            "m=repair_table_partitions, msg=method not implemented"
        )

    def drop_table(self, database_name, table_name):
        raise NotImplementedError("m=drop_table, msg=method not implemented")

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

    def add_partitions(self, database_name, table_name, partitions):
        raise NotImplementedError("m=add_partitions, msg=method not implemented")

    def create_new_partitions_from_df(
        self, database_name, table_name, df, partition_cols, parallelism=1
    ):
        raise NotImplementedError(
            "m=create_new_partitions_from_df, msg=method not implemented"
        )

    def get_table_schema(self, database_name, table_name):
        """
        Gets the table schema in Hive Metastore.

        :param database_name: database name of the table
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        :return: a list with the table columns
        :rtype: List[FieldSchema]
        """
        with self.client as conn:
            return conn.get_schema(database_name, table_name)

    def get_table_columns(self, database_name, table_name):
        """
        Fetches the table columns list from Hive Metastore.

        :param database_name: the database name of the table
        :param table_name: the table name
        :return: dictionary of columns types
        :rtype: Dict[str,str]
        """
        table_schema = self.get_table_schema(database_name, table_name)
        return self._get_columns_from_schema(table_schema)

    @staticmethod
    def _get_columns_from_schema(table_schema):
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
