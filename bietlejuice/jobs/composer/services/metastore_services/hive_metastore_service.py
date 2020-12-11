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
        :param table_schema: a list of tuples containing respectively the
         columns name and type (including partitioning columns).
        :type table_schema: List[Tuple(string, string)]
        :param partition_cols: a list of tuples containing respectively the
        columns name and type for the partition keys. A table can have one or
        more partitions keys. A separate data directory is created for each
        specified combination, which can improve query performance in some
        circumstances. Partitioned columns don't exist within the table data
        itself.
        :type partition_cols: List[Tuple(string, string)]
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

        :param table_columns: a list of tuples containing respectively the
        columns name and type
        :type table_columns: List[Tuple(string, string)]
        :return: columns list in the structure required by the Hive Metastore client
        :rtype: List[ColumnBuilder]
        """
        columns = []
        for col_name, col_type in table_columns:
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
        raise NotImplementedError("m=get_table_names, msg=method not implemented")

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
