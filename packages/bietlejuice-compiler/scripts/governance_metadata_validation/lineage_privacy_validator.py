"""Validate PII privacy propagation via column lineage."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import yaml

from scripts.governance_metadata_validation.pii_privacy_checks import (
    build_privacy_entity_index,
    build_table_subjects_index,
    parse_lineage_ref,
    subjects_compatible,
    table_key,
    table_privacy_subjects,
)

OUT_OF_REPO_PREFIXES = ("cdp_", "delta.")


def _is_out_of_repo_scope(database_name: str) -> bool:
    return database_name.startswith(OUT_OF_REPO_PREFIXES)


def _lineage_ref_id_entity(
    database_name: str, table_name: str, column_name: str, json_path: Optional[str]
) -> str:
    base = f"{database_name}.{table_name}.{column_name}"
    if json_path:
        normalized = json_path if json_path.startswith("$.") else f"$.{json_path}"
        return f"{base}#{normalized}"
    return base


def validate_metadata_lineage_privacy(
    metadata: Dict[str, Any],
    entity_index: Dict[str, Dict[str, Any]],
    table_subjects_index: Dict[Tuple[str, str], List[str]],
    metadata_path: str,
) -> Tuple[List[str], List[str]]:
    """Returns (errors, warnings)."""
    errors: List[str] = []
    warnings: List[str] = []
    downstream_table_subjects = table_privacy_subjects(metadata) or []
    columns = metadata.get("columns") or {}

    for column_name, column_def in columns.items():
        if not isinstance(column_def, dict):
            continue
        privacy = column_def.get("privacy")
        if not privacy:
            continue
        lineages = column_def.get("lineage") or []
        if not lineages:
            continue

        downstream_pii = privacy.get("piiType")
        has_json_paths = bool(privacy.get("jsonPaths"))
        if not downstream_pii and not has_json_paths:
            continue
        if has_json_paths and not downstream_pii:
            warnings.append(
                f"{metadata_path} column '{column_name}': jsonPaths lineage is not "
                "validated yet"
            )

        for ref in lineages:
            try:
                up_db, up_table, up_col, up_json = parse_lineage_ref(ref)
            except ValueError as exc:
                warnings.append(
                    f"{metadata_path} column '{column_name}': invalid lineage ref "
                    f"'{ref}': {exc}"
                )
                continue

            if _is_out_of_repo_scope(up_db):
                warnings.append(
                    f"{metadata_path} column '{column_name}': lineage '{ref}' "
                    "is out of repo scope (skipped)"
                )
                continue

            up_id = _lineage_ref_id_entity(up_db, up_table, up_col, up_json)
            upstream = entity_index.get(up_id)
            upstream_table_subjects = table_subjects_index.get(
                table_key(up_db, up_table)
            )

            if upstream_table_subjects and downstream_table_subjects:
                if not subjects_compatible(
                    downstream_table_subjects, upstream_table_subjects
                ):
                    msg = (
                        f"{metadata_path}: table privacy.dataSubjectType "
                        f"{downstream_table_subjects} is incompatible with "
                        f"upstream table {up_db}.{up_table} "
                        f"{upstream_table_subjects}"
                    )
                    if msg not in errors:
                        errors.append(msg)

            if not upstream and not upstream_table_subjects:
                warnings.append(
                    f"{metadata_path} column '{column_name}': pending_upstream "
                    f"({up_id} has no privacy classification yet)"
                )
                continue
            if not upstream and upstream_table_subjects and downstream_pii:
                warnings.append(
                    f"{metadata_path} column '{column_name}': pending_upstream "
                    f"({up_id} has no privacy classification yet)"
                )
                continue

            if upstream and downstream_pii:
                up_pii = upstream.get("piiType")
                if up_pii and up_pii != downstream_pii:
                    msg = (
                        f"{metadata_path} column '{column_name}': piiType "
                        f"'{downstream_pii}' diverges from upstream '{up_id}' "
                        f"piiType '{up_pii}'"
                    )
                    errors.append(msg)

    return errors, warnings


def validate_lineage_privacy_for_files(
    metadata_paths: List[Path],
    all_metadata_paths: List[Path],
) -> Tuple[List[str], List[str]]:
    entity_index = build_privacy_entity_index(all_metadata_paths)
    table_subjects_index = build_table_subjects_index(all_metadata_paths)
    errors: List[str] = []
    warnings: List[str] = []

    for path in metadata_paths:
        with open(path, encoding="utf-8") as handle:
            metadata = yaml.safe_load(handle) or {}
        file_errors, file_warnings = validate_metadata_lineage_privacy(
            metadata,
            entity_index,
            table_subjects_index,
            str(path),
        )
        errors.extend(file_errors)
        warnings.extend(file_warnings)

    return errors, warnings
