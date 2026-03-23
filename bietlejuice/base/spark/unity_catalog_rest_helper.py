"""
Helper for Unity Catalog REST API operations from non-Databricks
environments (EMR).

Analogous to ``GlueCatalogHelper`` but for the UC REST API direction.
Handles client caching and provides a non-blocking ``sync_table_to_uc``
convenience method.
"""

from __future__ import annotations

import os

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("UnityCatalogRestHelper")


class UnityCatalogRestHelper:

    _uc_rest_client = None

    @staticmethod
    def is_uc_rest_enabled() -> bool:
        """Return ``True`` when UC REST sync is available.

        UC REST is considered enabled when ``DATABRICKS_UC_HOST`` is
        set (a token is also required but may come from OAuth).
        """
        if os.environ.get("UC_REST_DISABLED", "").lower() == "true":
            return False
        return bool(os.environ.get("DATABRICKS_UC_HOST"))

    @staticmethod
    def get_uc_rest_client():
        """Return a cached ``UnityCatalogRestClient`` instance."""
        if UnityCatalogRestHelper._uc_rest_client is None:
            from bietlejuice.clients.db_clients.unity_catalog_rest_client import (
                UnityCatalogRestClient,
            )

            UnityCatalogRestHelper._uc_rest_client = UnityCatalogRestClient()
        return UnityCatalogRestHelper._uc_rest_client

    @staticmethod
    def reset_client() -> None:
        """Clear the cached client (useful for tests)."""
        UnityCatalogRestHelper._uc_rest_client = None

    @staticmethod
    def sync_table_to_uc(
        database_name: str,
        table_name: str,
        table_location: str,
        table_schema,
        partitions: list,
        format_str: str = "DELTA",
    ) -> None:
        """Register a table in Unity Catalog via REST API if enabled.

        Failures are logged and do **not** propagate so they never block
        the Spark pipeline.
        """
        if not UnityCatalogRestHelper.is_uc_rest_enabled():
            logger.warning(
                f"m=sync_table_to_uc, table={database_name}.{table_name}, "
                "DATABRICKS_UC_HOST=%s, msg=UC REST is not enabled, skipping sync",
                os.environ.get("DATABRICKS_UC_HOST", "<not set>"),
            )
            return
        try:
            from bietlejuice.services.metastore_services.unity_catalog_rest_metastore_service import (
                UnityCatalogRestMetastoreService,
            )

            uc_service = UnityCatalogRestMetastoreService(
                UnityCatalogRestHelper.get_uc_rest_client()
            )
            uc_service.create_database(database_name)
            uc_service.create_external_table(
                database_name=database_name,
                table_name=table_name,
                table_location=table_location,
                table_schema=table_schema,
                partition_cols=partitions,
                format_options=format_str,
            )
            logger.info(
                f"m=sync_table_to_uc, table={database_name}.{table_name}, "
                "msg=table synced to UC successfully"
            )
        except Exception as exc:
            logger.warning(
                f"m=sync_table_to_uc, table={database_name}.{table_name}, "
                f"error={exc}, msg=UC REST sync failed, continuing"
            )
