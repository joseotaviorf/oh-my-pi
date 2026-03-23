"""
Helper for AWS Glue Data Catalog operations.

Analogous to ``UnityCatalogHelper`` but for Glue.  Handles environment
detection and provides a cached ``GlueClient`` with STS assume-role
support.

Glue database names match Spark database names exactly — no suffix or
translation is applied.
"""

from __future__ import annotations

import os

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("GlueCatalogHelper")


class GlueCatalogHelper:

    _glue_client = None

    @staticmethod
    def is_glue_catalog_enabled() -> bool:
        """Return ``True`` when Glue sync is available in this environment.

        Glue is considered enabled when the ``GLUE_ASSUME_ROLE_ARN``
        environment variable is set **or** when running on an AWS-native
        environment where default credentials can reach Glue.

        Local dev environments without AWS credentials will return
        ``False``, causing the framework to skip Glue registration
        gracefully.
        """
        if os.environ.get("GLUE_CATALOG_DISABLED", "").lower() == "true":
            return False
        if os.environ.get("GLUE_ASSUME_ROLE_ARN"):
            return True
        try:
            import boto3

            boto3.client("sts").get_caller_identity()
            return True
        except Exception:
            return False

    @staticmethod
    def get_glue_client():
        """Return a cached ``GlueClient`` instance.

        Lazy-imported to avoid pulling boto3 into contexts that never
        use Glue (e.g. local unit tests without AWS credentials).
        """
        if GlueCatalogHelper._glue_client is None:
            from bietlejuice.clients.db_clients.glue_client import GlueClient

            GlueCatalogHelper._glue_client = GlueClient()
        return GlueCatalogHelper._glue_client

    @staticmethod
    def reset_client() -> None:
        """Clear the cached client (useful for tests)."""
        GlueCatalogHelper._glue_client = None

    @staticmethod
    def sync_table_to_glue(
        database_name: str,
        table_name: str,
        table_location: str,
        table_schema,
        partitions: list,
        format_str: str = "DELTA",
    ) -> None:
        """Register a table in the Glue Data Catalog if Glue is enabled.

        Analogous to ``UnityCatalogHelper.sync_table_to_unity_catalog``
        but for Glue.  Failures are logged and do **not** propagate so
        they never block the Spark pipeline.

        :param database_name: Glue database name (same as Spark).
        :param table_name: Table name.
        :param table_location: S3 path of the table data.
        :param table_schema: ``OrderedDict`` of ``{col: type}``.
        :param partitions: Partition column names or ``(name, type)`` tuples.
        :param format_str: Table format (``"DELTA"``, ``"PARQUET"``, …).
        """
        if not GlueCatalogHelper.is_glue_catalog_enabled():
            return
        try:
            from bietlejuice.services.metastore_services.glue_metastore_service import (
                GlueMetastoreService,
            )

            glue_service = GlueMetastoreService(GlueCatalogHelper.get_glue_client())
            glue_service.create_database(database_name)
            glue_service.create_external_table(
                database_name=database_name,
                table_name=table_name,
                table_location=table_location,
                table_schema=table_schema,
                partition_cols=partitions,
                format_options=format_str,
            )
            logger.info(
                f"m=sync_table_to_glue, table={database_name}.{table_name}, "
                "msg=table synced to Glue successfully"
            )
        except Exception as exc:
            logger.warning(
                f"m=sync_table_to_glue, table={database_name}.{table_name}, "
                f"error={exc}, msg=Glue sync failed, continuing"
            )
