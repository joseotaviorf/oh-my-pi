from typing import List, Tuple

from hive_metastore_client import HiveMetastoreClient

from bietlejuice.jobs.composer.loaders import HiveMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import HiveMetastoreService


class SyncMetastoreExternalTablePartitionsPipeline:
    """Class to synchronize an external table partitions in Hive metastore."""

    def __init__(
        self,
        metastore_host: str,
        database_name: str,
        table_name: str,
        partition_keys: List[Tuple[str, str]],
        partition_values: List[List[str]] = None,
    ):
        """
        Constructor.

        :param metastore_host: the host of Hive Metastore
        :param database_name: the database name
        :param table_name: the table name
        :param partition_keys: a list of tuples containing respectively the
        columns name and type for the partition keys. A table can have one or
        more partitions keys. A separate data directory is created for each
        specified combination, which can improve query performance in some
        circumstances. Partitioned columns don't exist within the table data
        itself.
        :param partition_values: A list containing lists of partitions values.
        Each table can have multiple partitions, that work as a hierarchy, thus
        the inner lists should contain those values in the correct hierarchy order.
        The user may want to add multiple partitions values in a single call, then
        the outer lists are just the collection of the inner ones.
        """
        self.metastore_host = metastore_host
        self.database_name = database_name
        self.table_name = table_name
        self.partition_keys = partition_keys
        self.partition_values = partition_values

    def run(self):
        """Syncs the external table partitions in Metastore."""

        hms_client = HiveMetastoreClient(self.metastore_host)
        hms_service = HiveMetastoreService(hms_client)
        hms_loader = HiveMetastoreLoader(hms_service)
        if self.partition_keys:
            hms_loader.update_table_partitions(
                database_name=self.database_name,
                table_name=self.table_name,
                partition_values=self.partition_values,
            )
