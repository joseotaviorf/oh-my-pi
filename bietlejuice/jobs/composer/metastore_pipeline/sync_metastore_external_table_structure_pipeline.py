import collections
from typing import List, Tuple

from hive_metastore_client import HiveMetastoreClient

from bietlejuice.jobs.composer.base.hive.table_format_info import TableFormatInfo
from bietlejuice.jobs.composer.loaders import HiveMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import HiveMetastoreService


class SyncMetastoreExternalTableStructurePipeline:
    """Class to create an external table in Hive metastore."""

    def __init__(
        self,
        metastore_host: str,
        database_name: str,
        table_name: str,
        database_location: str,
        table_schema: collections.OrderedDict,
        partition_keys: List[Tuple[str, str]],
        format_info: TableFormatInfo,
    ):
        """
        Constructor.

        :param metastore_host: the host of Hive Metastore
        :param database_name: the database name
        :param table_name: the table name
        :param database_location: s3 path where the database is located.
         E.g: s3://some/path/
        :param table_schema: an ordered dict containing the columns name and
         type (including partitioning columns). This will be the schema of the
         table in Hive.
        :param partition_keys: a list of tuples containing respectively the
        columns name and type for the partition keys. A table can have one or
        more partitions keys. A separate data directory is created for each
        specified combination, which can improve query performance in some
        circumstances. Partitioned columns don't exist within the table data
        itself.
        :param format_info: one of TableStorageDescriptor valid layers format.
         This gives information about the table storage parameters.
         E.g. TableStorageDescriptor.RAW_FORMAT
        :type format_info: bietlejuice.jobs.composer.base.hive.TableFormatInfo
        """
        self.metastore_host = metastore_host
        self.database_name = database_name
        self.table_name = table_name
        self.database_location = database_location
        self.table_schema = table_schema
        self.partition_keys = partition_keys
        self.format_info = format_info

    def run(self):
        """Creates or updates the external table in Metastore."""

        hms_client = HiveMetastoreClient(self.metastore_host)
        hms_service = HiveMetastoreService(hms_client)
        hms_loader = HiveMetastoreLoader(hms_service)

        hms_service.create_database(self.database_name)  # if not exists
        hms_loader.sync_metastore(
            database_name=self.database_name,
            table_name=self.table_name,
            database_location=self.database_location,
            table_schema=self.table_schema,
            partition_keys=self.partition_keys,
            format_info=self.format_info,
            source_schema=self.table_schema,
        )
