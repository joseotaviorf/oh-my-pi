"""
Loads table schemas into the AWS Glue Data Catalog.

Follows the same pattern as ``HiveMetastoreLoader``: compares the
source schema (from Spark metastore) with what is currently registered
in Glue and creates or updates the table as needed.
"""

from __future__ import annotations

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("GlueMetastoreLoader")


class GlueMetastoreLoader:
    """Syncs table schemas from Spark metastore into AWS Glue."""

    def __init__(self, glue_metastore_service):
        """
        :param glue_metastore_service: ``GlueMetastoreService`` instance.
        """
        self.glue_metastore_service = glue_metastore_service

    def sync_metastore(
        self,
        database_name,
        table_name,
        database_location,
        table_schema,
        partition_keys,
        format_options,
    ):
        """Create or update a table in the Glue Data Catalog.

        :param database_name: Target Glue database (same as Spark database).
        :param table_name: Table name.
        :param database_location: S3 path of the database root
            (e.g. ``s3a://bucket/raw/source/``).
        :param table_schema: ``OrderedDict`` of ``{col_name: col_type}``.
        :param partition_keys: List of partition column names or
            ``(name, type)`` tuples.
        :param format_options: Table format string or format-info object.
        """
        table_s3_path = database_location + table_name

        self.glue_metastore_service.create_database(database_name)

        existing_tables = self.glue_metastore_service.get_table_names(database_name)
        action = "updating" if table_name in existing_tables else "creating"

        logger.info(
            f"m=sync_metastore, db={database_name}, table={table_name}, "
            f"msg={action} table in Glue"
        )

        self.glue_metastore_service.create_external_table(
            database_name=database_name,
            table_name=table_name,
            table_location=table_s3_path,
            table_schema=table_schema,
            partition_cols=partition_keys or [],
            format_options=format_options,
        )

        logger.info(
            f"m=sync_metastore, db={database_name}, table={table_name}, "
            "msg=table synced to Glue successfully"
        )
