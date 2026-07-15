"""Databricks Commands API 1.2 client and result parsing."""

from __future__ import annotations

import json
import logging
import os
import subprocess
import time
from decimal import Decimal
from typing import Any, Dict, List, Optional

from models import ParsedResult

logger = logging.getLogger(__name__)

RESULT_MARKER = "MIGRATION_VALIDATE_RESULT"


def _normalize_cell(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, (int, float, bool)):
        return value
    if isinstance(value, Decimal):
        return str(value)
    return str(value)


def parse_command_result(results: Optional[Dict[str, Any]]) -> ParsedResult:
    """Parse Databricks Commands API ``results`` payload into columns and rows."""
    if not results:
        return ParsedResult(columns=[], rows=[], row_dicts=[])

    result_type = results.get("resultType", "")
    data = results.get("data")

    if result_type == "table":
        schema_entries = results.get("schema") or []
        columns = [str(entry.get("name", "")) for entry in schema_entries]
        rows = data if isinstance(data, list) else []
        row_dicts = []
        for row in rows:
            if not isinstance(row, list):
                continue
            row_dicts.append(
                {
                    columns[i]: _normalize_cell(row[i])
                    for i in range(min(len(columns), len(row)))
                }
            )
        return ParsedResult(columns=columns, rows=rows, row_dicts=row_dicts)

    if result_type == "text" and isinstance(data, str):
        lines = [line for line in data.strip().splitlines() if line.strip()]
        if not lines:
            return ParsedResult(columns=[], rows=[], row_dicts=[])
        columns = ["col_name", "data_type", "comment"]
        rows: List[List[Any]] = []
        row_dicts: List[Dict[str, Any]] = []
        for line in lines:
            parts = [part.strip() for part in line.split("\t")]
            if len(parts) < 2:
                parts = [part.strip() for part in line.split("|")]
            if len(parts) < 2:
                continue
            if parts[0].lower() in ("col_name", "# col_name"):
                continue
            row = parts[:3] + [""] * max(0, 3 - len(parts))
            rows.append(row[:3])
            row_dicts.append(
                {
                    "col_name": row[0],
                    "data_type": row[1],
                    "comment": row[2] if len(row) > 2 else "",
                }
            )
        return ParsedResult(columns=columns, rows=rows, row_dicts=row_dicts)

    return ParsedResult(columns=[], rows=[], row_dicts=[])


# Default UC catalog for DAG tables (matches spark.databricks.sql.initial.catalog.namespace).
_PROFILE_CATALOG = {
    "PROD": "quintoandar_prod",
    "FORNO": "quintoandar_forno",
}


class DatabricksAPI:
    """Databricks Commands API 1.2 client with polling."""

    def __init__(self, profile: str, cluster_id: str, timeout_sec: int = 600):
        self.profile = profile
        self.cluster_id = cluster_id
        self.timeout_sec = timeout_sec
        self.context_id: Optional[str] = None

    def _env(self) -> Dict[str, str]:
        env = os.environ.copy()
        env.pop("DATABRICKS_USERNAME", None)
        env["DATABRICKS_CONFIG_PROFILE"] = self.profile
        return env

    def _catalog_name(self) -> Optional[str]:
        override = os.environ.get("DATABRICKS_CATALOG", "").strip()
        if override:
            return override
        return _PROFILE_CATALOG.get(self.profile.upper())

    def _run_api(
        self,
        method: str,
        endpoint: str,
        payload: Dict[str, Any],
        timeout_sec: int = 120,
    ) -> Dict[str, Any]:
        cmd = ["databricks", "api", method, endpoint, "--profile", self.profile]
        cmd.extend(["--json", json.dumps(payload)])
        resp = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout_sec,
            env=self._env(),
        )
        if resp.returncode != 0:
            raise RuntimeError(resp.stderr.strip() or resp.stdout.strip())
        return json.loads(resp.stdout)

    def open_context(self) -> bool:
        try:
            data = self._run_api(
                "post",
                "/api/1.2/contexts/create",
                {"language": "sql", "clusterId": self.cluster_id},
            )
            self.context_id = data["id"]
            logger.info("Context opened: %s", self.context_id)
            catalog = self._catalog_name()
            if catalog:
                # All-purpose clusters often default to hive_metastore; DAG SQL expects UC.
                self.execute_sql(f"USE CATALOG {catalog}")
                logger.info("Using catalog: %s", catalog)
            return True
        except Exception as exc:
            logger.error("Failed to open context: %s", exc)
            return False

    def close_context(self) -> bool:
        if not self.context_id:
            return True
        try:
            self._run_api(
                "post",
                "/api/1.2/contexts/destroy",
                {"clusterId": self.cluster_id, "contextId": self.context_id},
            )
            logger.info("Context closed")
            return True
        except Exception as exc:
            logger.error("Failed to close context: %s", exc)
            return False

    def execute_sql(self, sql: str) -> ParsedResult:
        """Execute SQL and return parsed table/text results.

        Callers must pass SQL built by ``query_builders`` from repo-pinned DAG
        query files (``load_pinned_sql``) with validated ORDER BY identifiers.
        Do not pass raw CLI arguments or other unsanitized input.
        """
        if not self.context_id:
            raise RuntimeError("Context not opened")

        data = self._run_api(
            "post",
            "/api/1.2/commands/execute",
            {
                "language": "sql",
                "clusterId": self.cluster_id,
                "contextId": self.context_id,
                "command": sql,
            },
        )
        cmd_id = data["id"]
        start_time = time.time()

        while time.time() - start_time < self.timeout_sec:
            status_data = self._run_api(
                "get",
                "/api/1.2/commands/status",
                {
                    "clusterId": self.cluster_id,
                    "contextId": self.context_id,
                    "commandId": cmd_id,
                },
            )
            status = status_data.get("status")
            if status == "Finished":
                results = status_data.get("results") or status_data.get("result")
                return parse_command_result(results)
            if status == "Error":
                results = status_data.get("results") or {}
                cause = results.get("cause") or results.get("summary") or status_data
                raise RuntimeError(f"Databricks SQL error: {cause}")
            time.sleep(2)

        raise TimeoutError(f"Command timeout after {self.timeout_sec}s")
