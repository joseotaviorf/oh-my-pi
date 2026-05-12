"""
Client for Databricks Unity Catalog REST API.

Wraps ``databricks.sdk.WorkspaceClient`` to register schemas and
external tables in Unity Catalog from non-Databricks environments
(e.g. EMR).

Authentication uses OAuth client credentials or a Personal Access Token,
following the same pattern already used in
``dags/platform/enrich_databricks/spark_jobs/load_instance_pools.py``.
"""

from __future__ import annotations

import os
from typing import Dict, List, Optional

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.clients.db_clients.db_client import DBClient

logger = QuintoAndarLogger("UnityCatalogRestClient")


class UnityCatalogRestClient(DBClient):
    """Thin wrapper around ``databricks.sdk.WorkspaceClient`` for Unity
    Catalog schema and table management.

    :param host: Databricks workspace URL.  Falls back to
        ``DATABRICKS_UC_HOST`` env var.
    :param token: PAT or OAuth token.  Falls back to
        ``DATABRICKS_UC_TOKEN`` env var.
    """

    def __init__(
        self,
        host: Optional[str] = None,
        token: Optional[str] = None,
    ):
        self._host = host or os.environ.get("DATABRICKS_UC_HOST")
        self._token = token or os.environ.get("DATABRICKS_UC_TOKEN")
        self._workspace_client = None

    @property
    def conn(self):
        """Return a ready-to-use ``WorkspaceClient``."""
        if self._workspace_client is None:
            self._workspace_client = self._build_client()
        return self._workspace_client

    def _build_client(self):
        from databricks.sdk import WorkspaceClient

        if not self._host:
            raise ValueError("DATABRICKS_UC_HOST env var or host parameter is required")
        logger.info(
            f"m=_build_client, host={self._host}, "
            "msg=Creating WorkspaceClient for UC REST API"
        )
        return WorkspaceClient(host=self._host, token=self._token)

    # -- DBClient interface --------------------------------------------------

    def get_records(self, query, parameters=None):
        raise NotImplementedError(
            "UnityCatalogRestClient does not support SQL queries. "
            "Use the dedicated methods instead."
        )

    def run(self, command, autocommit=False, parameters=None):
        raise NotImplementedError(
            "UnityCatalogRestClient does not support raw SQL commands. "
            "Use the dedicated methods instead."
        )

    # -- Schema (database) operations ----------------------------------------

    def ensure_schema(
        self,
        catalog_name: str,
        schema_name: str,
        comment: str = "",
    ) -> None:
        """Create a UC schema if it does not already exist."""
        try:
            self.conn.schemas.get(full_name=f"{catalog_name}.{schema_name}")
            logger.info(
                f"m=ensure_schema, schema={catalog_name}.{schema_name}, "
                "msg=schema already exists in UC"
            )
        except Exception:
            logger.info(
                f"m=ensure_schema, schema={catalog_name}.{schema_name}, "
                "msg=creating schema in UC"
            )
            self.conn.schemas.create(
                name=schema_name,
                catalog_name=catalog_name,
            )

    # -- Table operations ----------------------------------------------------

    def create_table(
        self,
        catalog_name: str,
        schema_name: str,
        table_name: str,
        columns: List[Dict],
        storage_location: str,
        data_source_format: str = "DELTA",
    ) -> None:
        """Create an external table in Unity Catalog."""
        from databricks.sdk.service.catalog import (
            DataSourceFormat,
            TableType,
        )

        col_infos = self._build_column_infos(columns)
        fmt = DataSourceFormat[data_source_format.upper()]

        self.conn.tables.create(
            name=table_name,
            catalog_name=catalog_name,
            schema_name=schema_name,
            table_type=TableType.EXTERNAL,
            data_source_format=fmt,
            storage_location=storage_location,
            columns=col_infos,
        )

    @classmethod
    def _build_column_infos(cls, columns: List[Dict]) -> list:
        """Build ``ColumnInfo`` list with all required fields:
        ``name``, ``type_text``, ``type_name``, ``type_json``, ``position``.
        """
        from databricks.sdk.service.catalog import ColumnInfo, ColumnTypeName

        col_infos = []
        for idx, c in enumerate(columns):
            type_text = c["type_text"].lower()
            type_name_enum = cls._resolve_column_type_name(
                ColumnTypeName, c["type_text"]
            )
            type_json = cls._type_text_to_json(type_text)

            col_infos.append(
                ColumnInfo(
                    name=c["name"],
                    type_text=type_text,
                    type_name=type_name_enum,
                    type_json=type_json,
                    position=idx,
                    nullable=True,
                )
            )
        return col_infos

    _TYPE_TEXT_TO_JSON: Dict[str, str] = {
        "boolean": '"boolean"',
        "tinyint": '"byte"',
        "byte": '"byte"',
        "smallint": '"short"',
        "short": '"short"',
        "int": '"integer"',
        "integer": '"integer"',
        "bigint": '"long"',
        "long": '"long"',
        "float": '"float"',
        "double": '"double"',
        "date": '"date"',
        "timestamp": '"timestamp"',
        "timestamp_ntz": '"timestamp_ntz"',
        "string": '"string"',
        "binary": '"binary"',
        "void": '"void"',
    }

    @classmethod
    def _type_text_to_json(cls, type_text: str) -> str:
        """Convert a type_text (e.g. 'string', 'bigint') to its
        type_json representation (e.g. '"string"', '"long"')."""
        lower = type_text.strip().lower()
        if lower in cls._TYPE_TEXT_TO_JSON:
            return cls._TYPE_TEXT_TO_JSON[lower]
        if lower.startswith("decimal"):
            return '"decimal"'
        return '"string"'

    @staticmethod
    def _resolve_column_type_name(column_type_name_enum, type_text: str):
        """Map a type_text string (e.g. 'STRING', 'INT') to the SDK
        ``ColumnTypeName`` enum.  Falls back to ``STRING`` for complex
        or unrecognized types."""
        base = type_text.strip().upper().split("(")[0].split("<")[0]
        try:
            return column_type_name_enum[base]
        except KeyError:
            return column_type_name_enum["STRING"]

    def delete_table(self, full_table_name: str) -> None:
        """Delete a table from Unity Catalog."""
        try:
            self.conn.tables.delete(full_name=full_table_name)
        except Exception as exc:
            logger.info(
                f"m=delete_table, table={full_table_name}, "
                f"error={exc}, msg=table not found in UC, skipping"
            )

    def get_table(self, full_table_name: str) -> Optional[object]:
        """Retrieve a table from Unity Catalog.  Returns ``None`` if not
        found."""
        try:
            return self.conn.tables.get(full_name=full_table_name)
        except Exception:
            return None

    def list_tables(self, catalog_name: str, schema_name: str) -> List[str]:
        """List all table names in a UC schema."""
        names: List[str] = []
        for tbl in self.conn.tables.list(
            catalog_name=catalog_name, schema_name=schema_name
        ):
            names.append(tbl.name)
        return names
