"""PII privacy section checks against pii_catalog and anonymization controls."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple

import yaml


def _find_repo_root(start: Path = Path(__file__).resolve()) -> Path:
    """Locate the monorepo root by its stable signature (``dags/`` + ``packages/``).

    Avoids hardcoding this file's depth in the package tree, so moving the
    script within bietlejuice-compiler does not silently break path resolution.
    """
    for parent in (start, *start.parents):
        if (parent / "dags").is_dir() and (parent / "packages").is_dir():
            return parent
    return start.parents[4]  # historical layout fallback


REPO_ROOT = _find_repo_root()
# Single source of truth for the governance policy tree. If the folder ever
# moves (e.g. into bietlejuice-compiler), change only this line.
GOVERNANCE_POLICY_ROOT = REPO_ROOT / "governance"
CATALOG_PATH = GOVERNANCE_POLICY_ROOT / "pii_catalog" / "pii_catalog.yml"
CONTROLS_DIR = GOVERNANCE_POLICY_ROOT / "pii_anonymization_controls"

ALLOWED_DATA_SUBJECT_TYPES = frozenset({"customer", "employee", "partner"})
JSON_PATH_SEP = "#"


def load_pii_catalog(catalog_path: Path = CATALOG_PATH) -> Dict[str, Any]:
    with open(catalog_path, encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def load_pii_catalog_types(catalog_path: Path = CATALOG_PATH) -> Set[str]:
    return set(load_pii_catalog(catalog_path).get("types", {}).keys())


def catalog_classification_for(
    pii_type: str, catalog: Optional[Dict[str, Any]] = None
) -> Optional[str]:
    if catalog is None:
        catalog = load_pii_catalog()
    return (catalog.get("types", {}).get(pii_type) or {}).get("classification")


def load_anonymization_controls(
    controls_dir: Path = CONTROLS_DIR,
) -> List[Dict[str, str]]:
    controls: List[Dict[str, str]] = []
    if not controls_dir.is_dir():
        return controls
    for path in sorted(controls_dir.glob("*.yml")):
        with open(path, encoding="utf-8") as handle:
            data = yaml.safe_load(handle) or {}
        for entry in data.get("controls", []):
            if not isinstance(entry, dict):
                continue
            id_entity = entry.get("id_entity")
            rae_id = entry.get("rae_id")
            if id_entity and rae_id:
                controls.append({"id_entity": str(id_entity), "rae_id": str(rae_id)})
    return controls


def build_id_entity(database_name: str, table_name: str, column_name: str) -> str:
    return f"{database_name}.{table_name}.{column_name}"


def build_json_path_id_entity(
    database_name: str, table_name: str, column_name: str, json_path: str
) -> str:
    normalized = json_path if json_path.startswith("$.") else f"$.{json_path}"
    return f"{build_id_entity(database_name, table_name, column_name)}#{normalized}"


def parse_lineage_ref(ref: str) -> Tuple[str, str, str, Optional[str]]:
    """Parse database.table.column or database.table.column#$.path."""
    raw = (ref or "").strip()
    json_path: Optional[str] = None
    base = raw
    if JSON_PATH_SEP in raw:
        base, json_path = raw.split(JSON_PATH_SEP, 1)
        json_path = json_path.strip() or None

    parts = base.split(".")
    if len(parts) < 3:
        raise ValueError(f"lineage ref must be database.table.column: {raw}")

    column_name = parts[-1]
    table_name = parts[-2]
    database_name = ".".join(parts[:-2])
    return database_name, table_name, column_name, json_path


def table_key(database_name: str, table_name: str) -> Tuple[str, str]:
    return (database_name, table_name)


def table_privacy_subjects(metadata: Dict[str, Any]) -> Optional[List[str]]:
    table_privacy = metadata.get("privacy")
    if not isinstance(table_privacy, dict):
        return None
    subjects = table_privacy.get("dataSubjectType")
    if not subjects:
        return None
    return list(subjects)


def resolve_effective_subjects(
    metadata: Dict[str, Any],
    column_def: Optional[Dict[str, Any]] = None,
    json_entry: Optional[Dict[str, Any]] = None,
) -> List[str]:
    """Effective dataSubjectType: jsonPath override > column override > table-level."""
    resolved: Optional[List[str]] = None

    if json_entry and json_entry.get("dataSubjectType"):
        resolved = list(json_entry["dataSubjectType"])
    elif column_def and isinstance(column_def.get("privacy"), dict):
        col_privacy = column_def["privacy"]
        if col_privacy.get("dataSubjectType"):
            resolved = list(col_privacy["dataSubjectType"])

    if resolved is None:
        table_subjects = table_privacy_subjects(metadata)
        if table_subjects:
            resolved = list(table_subjects)

    return resolved or []


def subjects_compatible(downstream: Iterable[str], upstream: Iterable[str]) -> bool:
    """Downstream table subjects must be equal or a superset of upstream."""
    down = set(downstream)
    up = set(upstream)
    if not up:
        return True
    if not down:
        return False
    return up.issubset(down)


def effective_requires_mask(data_subject_types: Iterable[str]) -> bool:
    return "customer" in set(data_subject_types)


def _privacy_with_effective_subjects(
    privacy: Dict[str, Any], effective_subjects: List[str]
) -> Dict[str, Any]:
    merged = dict(privacy)
    if effective_subjects:
        merged["dataSubjectType"] = effective_subjects
    return merged


def iter_privacy_entities_from_metadata(
    metadata: Dict[str, Any],
) -> List[Tuple[str, str, Dict[str, Any]]]:
    database_name = metadata.get("database_name", "")
    table_name = metadata.get("table_name", "")
    columns = metadata.get("columns") or {}
    entities: List[Tuple[str, str, Dict[str, Any]]] = []

    for column_name, column_def in columns.items():
        if not isinstance(column_def, dict):
            continue
        privacy = column_def.get("privacy")
        if not privacy:
            continue

        scalar_subjects = resolve_effective_subjects(metadata, column_def)
        if privacy.get("piiType"):
            entities.append(
                (
                    build_id_entity(database_name, table_name, column_name),
                    column_name,
                    _privacy_with_effective_subjects(privacy, scalar_subjects),
                )
            )

        for json_entry in privacy.get("jsonPaths") or []:
            if not isinstance(json_entry, dict):
                continue
            path = json_entry.get("path", "")
            normalized = path if path.startswith("$.") else f"$.{path}"
            path_subjects = resolve_effective_subjects(metadata, column_def, json_entry)
            entities.append(
                (
                    build_json_path_id_entity(
                        database_name, table_name, column_name, path
                    ),
                    f"{column_name}#{normalized}",
                    _privacy_with_effective_subjects(json_entry, path_subjects),
                )
            )
    return entities


def _validate_subjects_list(
    subjects: List[str], context: str, table_subjects: Optional[List[str]] = None
) -> List[str]:
    errors: List[str] = []
    invalid = [s for s in subjects if s not in ALLOWED_DATA_SUBJECT_TYPES]
    if invalid:
        errors.append(
            f"{context}: invalid dataSubjectType {invalid}; "
            f"allowed: {sorted(ALLOWED_DATA_SUBJECT_TYPES)}"
        )
    if table_subjects and subjects:
        col_set = set(subjects)
        table_set = set(table_subjects)
        if col_set != table_set and not col_set.issubset(table_set):
            errors.append(
                f"{context}: dataSubjectType {subjects} conflicts with table "
                f"privacy.dataSubjectType {table_subjects}"
            )
    return errors


def _validate_pii_type_slug(
    pii_type: Optional[str], catalog_types: Set[str], context: str
) -> List[str]:
    if pii_type and pii_type not in catalog_types:
        return [f"{context}: privacy.piiType '{pii_type}' is not in pii_catalog.yml"]
    return []


def validate_column_privacy_block(
    metadata: Dict[str, Any],
    column_def: Dict[str, Any],
    catalog_types: Set[str],
    context: str,
) -> List[str]:
    errors: List[str] = []
    privacy = column_def.get("privacy") or {}
    table_subjects = table_privacy_subjects(metadata)
    pii_type = privacy.get("piiType")
    column_subjects = privacy.get("dataSubjectType")
    json_paths = privacy.get("jsonPaths") or []

    if not pii_type and not json_paths:
        return errors

    if column_subjects:
        errors.extend(
            _validate_subjects_list(list(column_subjects), context, table_subjects)
        )

    if pii_type:
        errors.extend(_validate_pii_type_slug(pii_type, catalog_types, context))
        effective = resolve_effective_subjects(metadata, column_def)
        if not effective:
            errors.append(
                f"{context}: privacy.piiType requires privacy.dataSubjectType "
                "on the table or on this column"
            )

    seen_paths: Set[str] = set()
    for index, entry in enumerate(json_paths):
        if not isinstance(entry, dict):
            errors.append(f"{context}: jsonPaths[{index}] must be a mapping")
            continue
        sub_context = f"{context} jsonPaths[{index}]"
        path = entry.get("path")
        if not path:
            errors.append(f"{sub_context}: path is required")
            continue
        if path in seen_paths:
            errors.append(f"{sub_context}: duplicate jsonPaths path '{path}'")
        seen_paths.add(path)
        entry_pii = entry.get("piiType")
        if not entry_pii:
            errors.append(f"{sub_context}: piiType is required")
        else:
            errors.extend(
                _validate_pii_type_slug(entry_pii, catalog_types, sub_context)
            )
        entry_subjects = entry.get("dataSubjectType")
        if entry_subjects:
            errors.extend(
                _validate_subjects_list(
                    list(entry_subjects), sub_context, table_subjects
                )
            )
        if entry_pii and not resolve_effective_subjects(metadata, column_def, entry):
            errors.append(
                f"{sub_context}: piiType requires privacy.dataSubjectType on "
                "the table, column, or jsonPath entry"
            )

    return errors


def validate_table_privacy(metadata: Dict[str, Any]) -> List[str]:
    """Positive validation: table privacy is optional until post-backfill gate."""
    errors: List[str] = []
    table_privacy = metadata.get("privacy")
    if not table_privacy:
        return errors
    if not isinstance(table_privacy, dict):
        errors.append("table privacy must be a mapping")
        return errors
    subjects = table_privacy.get("dataSubjectType")
    if not subjects:
        errors.append(
            "table privacy.dataSubjectType must be a non-empty list when "
            "table privacy is set"
        )
        return errors
    invalid = [s for s in subjects if s not in ALLOWED_DATA_SUBJECT_TYPES]
    if invalid:
        errors.append(
            f"table privacy: invalid dataSubjectType {invalid}; "
            f"allowed: {sorted(ALLOWED_DATA_SUBJECT_TYPES)}"
        )
    extra_keys = set(table_privacy.keys()) - {"dataSubjectType"}
    if extra_keys:
        errors.append(
            f"table privacy: unsupported keys {sorted(extra_keys)}; "
            "only dataSubjectType is allowed at table level"
        )
    return errors


def validate_metadata_privacy(
    metadata: Dict[str, Any], catalog_types: Set[str]
) -> List[str]:
    errors: List[str] = []
    errors.extend(validate_table_privacy(metadata))

    columns = metadata.get("columns") or {}
    for column_name, column_def in columns.items():
        if not isinstance(column_def, dict):
            continue
        privacy = column_def.get("privacy")
        if not privacy:
            continue
        context = f"column '{column_name}'"
        errors.extend(
            validate_column_privacy_block(metadata, column_def, catalog_types, context)
        )

    return errors


def index_customer_privacy_entities(
    metadata_files: Iterable[Path],
) -> Dict[str, bool]:
    index: Dict[str, bool] = {}
    for path in metadata_files:
        with open(path, encoding="utf-8") as handle:
            metadata = yaml.safe_load(handle) or {}
        for id_entity, _col, privacy in iter_privacy_entities_from_metadata(metadata):
            subjects = privacy.get("dataSubjectType") or []
            has_customer = effective_requires_mask(subjects)
            index[id_entity] = index.get(id_entity, False) or has_customer
    return index


def validate_controls_against_privacy_index(
    controls: List[Dict[str, str]], privacy_index: Dict[str, bool]
) -> List[str]:
    errors: List[str] = []
    for entry in controls:
        id_entity = entry["id_entity"]
        if id_entity not in privacy_index:
            errors.append(
                f"RAE control for '{id_entity}' has no matching privacy section "
                "in any metadata file"
            )
        elif not privacy_index[id_entity]:
            errors.append(
                f"RAE control for '{id_entity}' requires privacy.dataSubjectType "
                "to include 'customer'"
            )
    return errors


def list_all_metadata_paths(dags_root: Path = REPO_ROOT / "dags") -> List[Path]:
    paths: List[Path] = []
    paths.extend(dags_root.glob("**/metadata/**/*.yml"))
    return sorted({p.resolve() for p in paths if p.is_file()})


def build_privacy_entity_index(
    metadata_files: Iterable[Path],
) -> Dict[str, Dict[str, Any]]:
    """id_entity -> {piiType, dataSubjectType, database_name, table_name, metadata_path}."""
    index: Dict[str, Dict[str, Any]] = {}
    for path in metadata_files:
        with open(path, encoding="utf-8") as handle:
            metadata = yaml.safe_load(handle) or {}
        database_name = metadata.get("database_name", "")
        table_name = metadata.get("table_name", "")
        table_subjects = table_privacy_subjects(metadata) or []

        for id_entity, _col, privacy in iter_privacy_entities_from_metadata(metadata):
            index[id_entity] = {
                "piiType": privacy.get("piiType"),
                "dataSubjectType": list(privacy.get("dataSubjectType") or []),
                "database_name": database_name,
                "table_name": table_name,
                "table_subjects": list(table_subjects),
                "metadata_path": str(path),
            }
    return index


def build_table_subjects_index(
    metadata_files: Iterable[Path],
) -> Dict[Tuple[str, str], List[str]]:
    """(database_name, table_name) -> table-level dataSubjectType."""
    index: Dict[Tuple[str, str], List[str]] = {}
    for path in metadata_files:
        with open(path, encoding="utf-8") as handle:
            metadata = yaml.safe_load(handle) or {}
        subjects = table_privacy_subjects(metadata)
        if not subjects:
            continue
        key = table_key(
            metadata.get("database_name", ""),
            metadata.get("table_name", ""),
        )
        index[key] = list(subjects)
    return index
