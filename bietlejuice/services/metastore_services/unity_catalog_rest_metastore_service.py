"""
MetastoreService implementation that registers table metadata in
Databricks Unity Catalog via the REST API.

Used when running on EMR (where Spark SQL targets Glue natively) to
cross-register tables into Unity Catalog.
"""

from __future__ import annotations

import os
from collections import OrderedDict
from typing import Dict, List, Optional

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.services.metastore_services.glue_type_mapper import (
    map_glue_type_to_uc,
)
from bietlejuice.services.metastore_services.metastore_service import (
    MetastoreService,
)

logger = QuintoAndarLogger("UnityCatalogRestMetastoreService")

_UC_CATALOGS = {"forno": "quintoandar_forno", "prod": "quintoandar_prod"}


def _get_uc_catalog() -> str:
    """Resolve the UC catalog name from the ``ENVIRONMENT`` env var."""
    env = os.environ.get("ENVIRONMENT", "").lower()
    if env not in _UC_CATALOGS:
        raise ValueError(
            f"ENVIRONMENT='{env}' is not mapped to a UC catalog. "
            f"Supported: {list(_UC_CATALOGS.keys())}"
        )
    return _UC_CATALOGS[env]


class UnityCatalogRestMetastoreService(MetastoreService):
    """Service to register and manage table metadata in Databricks Unity
    Catalog via the REST API.

    :param uc_rest_client: A ``UnityCatalogRestClient`` instance.
    :param catalog_name: Explicit UC catalog name.  When ``None``, resolved
        from the ``ENVIRONMENT`` env var.
    """

    def __init__(self, uc_rest_client, catalog_name: Optional[str] = None):
        self._client = uc_rest_client
        self._catalog = catalog_name or _get_uc_catalog()

    @property
    def client(self):
        return self._client

    # -- MetastoreService overrides ------------------------------------------

    def create_database(self, database_name: str) -> None:
        """Create a UC schema (database) if it does not already exist."""
        self._client.ensure_schema(
            catalog_name=self._catalog,
            schema_name=database_name,
            comment="Managed by bietlejuice — synced from Spark metastore",
        )
        logger.info(
            f"m=create_database, catalog={self._catalog}, "
            f"schema={database_name}, msg=schema ensured in UC"
        )

    def create_external_table(
        self,
        database_name: str,
        table_name: str,
        table_location: str,
        table_schema: OrderedDict,
        partition_cols: list,
        format_options,
    ) -> None:
        """Create or update an external table in Unity Catalog."""
        format_str = self._resolve_format(format_options)
        columns = self._build_uc_columns(table_schema, partition_cols)
        location = self._normalise_location(table_location)

        full_name = f"{self._catalog}.{database_name}.{table_name}"
        existing = self._client.get_table(full_name)

        if existing:
            logger.info(
                f"m=create_external_table, table={full_name}, "
                "msg=table exists in UC, dropping and recreating"
            )
            self._client.delete_table(full_name)

        logger.info(
            f"m=create_external_table, table={full_name}, " "msg=creating table in UC"
        )
        self._client.create_table(
            catalog_name=self._catalog,
            schema_name=database_name,
            table_name=table_name,
            columns=columns,
            storage_location=location,
            data_source_format=format_str,
        )

    def drop_table(self, database_name: str, table_name: str) -> None:
        full_name = f"{self._catalog}.{database_name}.{table_name}"
        self._client.delete_table(full_name)

    def get_table_names(self, database_name: str, regex: str = "*") -> List[str]:
        return self._client.list_tables(self._catalog, database_name)

    def repair_table_partitions(self, database_name: str, table_name: str) -> None:
        logger.info(
            f"m=repair_table_partitions, table={database_name}.{table_name}, "
            "msg=UC REST API does not support MSCK REPAIR. Skipping."
        )

    def add_partitions(self, database_name, table_name, partitions):
        logger.info(
            f"m=add_partitions, table={database_name}.{table_name}, "
            "msg=UC REST API does not support ADD PARTITION. Skipping."
        )

    # -- Internal helpers ----------------------------------------------------

    @staticmethod
    def _resolve_format(format_options) -> str:
        if isinstance(format_options, str):
            return format_options.upper()
        if isinstance(format_options, dict):
            return format_options.get("format", "PARQUET").upper()
        return "PARQUET"

    @staticmethod
    def _build_uc_columns(
        table_schema: OrderedDict, partition_cols: list
    ) -> List[Dict]:
        """Convert bietlejuice schema to UC column dicts."""
        cols: List[Dict] = []
        for col_name, col_type in table_schema.items():
            cols.append(
                {
                    "name": col_name,
                    "type_text": map_glue_type_to_uc(str(col_type)),
                }
            )
        return cols

    @staticmethod
    def _normalise_location(location: str) -> str:
        if location.startswith("s3a://"):
            return location.replace("s3a://", "s3://", 1)
        if location.startswith("s3n://"):
            return location.replace("s3n://", "s3://", 1)
        return location
