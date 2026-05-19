# -*- coding: utf-8 -*-
"""
Build a registry mapping clean source column FQNs to Core Model output columns.

Used by source_layer_validation to detect when new DAGs re-implement what a
core model already provides.

Registry is populated from core metadata files that carry a
``context_defining_tables`` annotation — a list of ``db.table`` strings that
identify which clean source tables are the primary entity tables for that core
model output table.  Only lineage entries whose source table appears in that
list are registered.

Key design decisions
--------------------
- First-wins on duplicate clean FQN (deterministic sort order via sorted glob).
- Lineage entries containing colons (e.g. ``table.col:value``) or not in the
  three-part ``db.table.column`` format are silently skipped.
- File-level YAML parse errors are silently caught; that file is skipped.
- If the dags/core/ directory is missing or any top-level error occurs, an
  empty registry is returned (check disabled for that run).
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Dict

import yaml


@dataclass
class CoreColumnEntry:
    dag_name: str  # e.g. "core_house"
    core_fqn: str  # e.g. "core_house.house.id_house"


def build_core_model_registry(
    dags_root: Path = Path("dags"),
) -> Dict[str, CoreColumnEntry]:
    """
    Return a dict mapping ``clean_db.table.column`` -> ``CoreColumnEntry``.

    Scans ``dags_root/core/*/metadata/core/*.yml`` files that declare a
    non-empty ``context_defining_tables`` list and registers columns whose
    lineage traces to one of those tables.
    """
    registry: Dict[str, CoreColumnEntry] = {}

    try:
        for metadata_file in sorted(dags_root.glob("core/*/metadata/core/*.yml")):
            try:
                raw = yaml.safe_load(metadata_file.read_text()) or {}
            except Exception as e:
                # Consider using a logger for better monitoring
                print(f"Warning: Failed to parse {metadata_file}: {e}")
                continue

            context_tables = set(raw.get("context_defining_tables") or [])
            if not context_tables:
                continue

            dag_name = raw.get("database_name", "")
            table_name = raw.get("table_name", "")
            if not dag_name or not table_name:
                continue

            for col_name, col_data in (raw.get("columns") or {}).items():
                for lineage_entry in (col_data or {}).get("lineage") or []:
                    if not isinstance(lineage_entry, str):
                        continue
                    if ":" in lineage_entry:
                        continue
                    parts = lineage_entry.split(".")
                    if len(parts) != 3:
                        continue
                    source_db_table = f"{parts[0]}.{parts[1]}"
                    if source_db_table not in context_tables:
                        continue
                    if lineage_entry not in registry:
                        registry[lineage_entry] = CoreColumnEntry(
                            dag_name=dag_name,
                            core_fqn=f"{dag_name}.{table_name}.{col_name}",
                        )
    except Exception as e:
        # Consider using a logger for better monitoring
        print(f"Error: Failed to build core model registry: {e}")
        return {}

    return registry
