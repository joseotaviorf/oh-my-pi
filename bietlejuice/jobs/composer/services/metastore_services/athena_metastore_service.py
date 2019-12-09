from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.services.metastore_services.metastore_service import (
    MetastoreService,
)

logger = QuintoAndarLogger("AthenaMetastoreService")


class AthenaMetastoreService(MetastoreService):
    """
    Service to interact with the Athena Metastore (Hive Metastore)

    :param athena_client: a client to interact with Athena Metastore
    :type athena_client: AthenaClient
    """

    def __init__(self, athena_client):
        self._client = athena_client

    @property
    def client(self):
        return self._client

    @logger
    def create_external_table(
        self,
        database_name,
        table_name,
        table_location,
        table_schema,
        partition_cols,
        format_options,
    ):
        """
        Creates an external table based on underlying data files that exists in
        Amazon S3.

        This method checks the types of the cols before calling the base class
        method. Athena doesn't recognize some types on JSON format, so they need to
        be converted to string.
        :param database_name: database name
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        :param table_location: specifies the location of the underlying data in S3 from
        which the table is created, for example, 's3://mystorage/'
        :param table_schema: specifies the name and type for each column to be
        created (including partitioning columns).
        :type table_schema: OrderedDict
        :param partition_cols: specifies the names of partition columns in case of
        existence. A table can have one or more partitions, which consist of a
        distinct column name and value combination. A separate data directory is
        created for each specified combination, which can improve query performance
        in some circumstances. Partitioned columns don't exist within the table data
        itself.
        :type partition_cols: list
        :param format_options: specifies the format of the data files,
        serde properties, and tlb properties.
        :type format_options: dict
        """
        # TODO: search more about this problem and find a better approach
        if format_options == TableStorageFormat.JSON:
            table_schema = OrderedDict(
                (
                    col,
                    col_type.lower()
                    .replace("timestamp", "string")
                    .replace("date", "string")
                    .replace("binary", "varchar(53535)"),
                )
                for col, col_type in table_schema.items()
            )

        super().create_external_table(
            database_name,
            table_name,
            table_location,
            table_schema,
            partition_cols,
            format_options,
        )
