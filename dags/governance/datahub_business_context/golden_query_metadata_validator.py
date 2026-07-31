"""Validate golden-query SQL against repo metadata YAML files under ``dags/``."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import yaml
from golden_query_schema_validator import _SKIPPED_METADATA_COLUMNS

_REPO_ROOT = Path(__file__).resolve().parents[3]
_DAGS_ROOT = _REPO_ROOT / "dags"


@dataclass
class TableMetadataEntry:
    columns: set[str]
    metadata_paths: list[str] = field(default_factory=list)


def _table_key(database_name: str, table_name: str) -> tuple[str, str]:
    return (database_name.strip().lower(), table_name.strip().lower())


def _columns_from_metadata(metadata: dict) -> set[str]:
    raw_columns = metadata.get("columns") or {}
    if not isinstance(raw_columns, dict):
        return set()
    return {
        str(name).lower()
        for name in raw_columns
        if name and str(name).lower() not in _SKIPPED_METADATA_COLUMNS
    }


def build_metadata_column_index(
    dags_root: Path | None = None,
) -> dict[tuple[str, str], TableMetadataEntry]:
    """Index ``(database_name, table_name)`` -> documented columns from metadata YAML."""
    root = (dags_root or _DAGS_ROOT).resolve()
    repo_root = _REPO_ROOT.resolve()
    index: dict[tuple[str, str], TableMetadataEntry] = {}
    for path in sorted(root.glob("**/metadata/**/*.yml")):
        if not path.is_file():
            continue
        try:
            metadata = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except (OSError, yaml.YAMLError):
            continue
        database_name = str(metadata.get("database_name") or "").strip()
        table_name = str(metadata.get("table_name") or "").strip()
        if not database_name or not table_name:
            continue
        key = _table_key(database_name, table_name)
        columns = _columns_from_metadata(metadata)
        try:
            rel_path = str(path.resolve().relative_to(repo_root))
        except ValueError:
            rel_path = str(path.resolve())
        if key not in index:
            index[key] = TableMetadataEntry(
                columns=set(columns), metadata_paths=[rel_path]
            )
            continue
        entry = index[key]
        entry.columns.update(columns)
        if rel_path not in entry.metadata_paths:
            entry.metadata_paths.append(rel_path)
    return index


@dataclass
class MetadataSchemaClient:
    """Schema lookups backed by the repo metadata index."""

    index: dict[tuple[str, str], TableMetadataEntry]
    dags_root_label: str = "dags/**/metadata/**/*.yml"

    def table_exists(self, schema: str, table: str) -> bool:
        return _table_key(schema, table) in self.index

    def column_names_for_table(self, schema: str, table: str) -> Optional[set[str]]:
        entry = self.index.get(_table_key(schema, table))
        if entry is None:
            return None
        return set(entry.columns)

    def table_source_hint(self, schema: str, table: str) -> str:
        entry = self.index.get(_table_key(schema, table))
        if entry is None:
            return f"no metadata YAML under {self.dags_root_label}"
        if len(entry.metadata_paths) == 1:
            return f"see {entry.metadata_paths[0]}"
        paths = ", ".join(entry.metadata_paths[:3])
        suffix = "…" if len(entry.metadata_paths) > 3 else ""
        return f"see metadata files: {paths}{suffix}"
