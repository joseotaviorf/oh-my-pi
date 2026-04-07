"""CLI argument encoding for optimize_delta_table Spark job (EMR-safe).

Lives under base.airflow (not base.spark) so importing task creators does not
execute spark/__init__.py, which initializes PySpark and breaks Airflow DAG parsing.
"""

from __future__ import annotations

import base64
import json
from typing import Any, Dict

# Prefix must stay in sync with OptimizeDeltaTableTaskCreator (EMR path only).
EMR_TABLES_B64_PREFIX = "B64:"


def encode_tables_json_for_emr_cli(tables_json: str) -> str:
    """Wrap JSON so EMR/YARN spark-submit does not split or mangle a multi-token string."""
    return EMR_TABLES_B64_PREFIX + base64.standard_b64encode(
        tables_json.encode("utf-8")
    ).decode("ascii")


def decode_tables_config_from_cli(tables_arg: str) -> Dict[str, Any]:
    """Inverse of encode_tables_json_for_emr_cli; accepts raw JSON (Databricks) or B64:… (EMR)."""
    stripped = tables_arg.strip()
    if stripped.startswith(EMR_TABLES_B64_PREFIX):
        raw = base64.standard_b64decode(
            stripped[len(EMR_TABLES_B64_PREFIX) :].encode("ascii")
        )
        return json.loads(raw.decode("utf-8"))
    return json.loads(stripped)
