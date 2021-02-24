from hive_metastore_client import HiveMetastoreClient

from bietlejuice.jobs.composer.loaders import HiveMetastoreLoader
from bietlejuice.jobs.composer.pipeline.abstract_pipeline import AbstractPipeline
from bietlejuice.jobs.composer.services.metastore_services import HiveMetastoreService


class MetastoreExternalTablePipeline(AbstractPipeline):
    """Class to create an external table in Hive metastore."""

    def __init__(
        self,
        metastore_host,
        database_name,
        table_name,
        database_location,
        table_schema,
        partition_keys,
        partition_values,
        format_info,
    ):
        """
        Constructor.

        :param metastore_host: the host of Hive Metastore
        :type metastore_host: str
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
        :param partition_values: A list containing lists of partitions values.
        Each table can have multiple partitions, that work as a hierarchy, thus
        the inner lists should contain those values in the correct hierarchy order.
        The user may want to add multiple partitions values in a single call, then
        the outer lists are just the collection of the inner ones.
        :type partition_values: List[List[str]]
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
        self.partition_values = partition_values
        self.format_info = format_info

    def run(self):
        """Creates the external table in Metastore."""

        hms_client = HiveMetastoreClient(self.metastore_host)
        hms_service = HiveMetastoreService(hms_client)

        hms_service.create_database(self.database_name)

        hms_loader = HiveMetastoreLoader(hms_service)
        hms_loader.update_metastore(
            database_name=self.database_name,
            table_name=self.table_name,
            database_location=self.database_location,
            table_schema=self.table_schema,
            partition_keys=self.partition_keys,
            format_info=self.format_info,
            source_schema=self.table_schema,
        )

        hms_loader.update_table_partitions(
            database_name=self.database_name,
            table_name=self.table_name,
            partition_values=self.partition_values,
        )
