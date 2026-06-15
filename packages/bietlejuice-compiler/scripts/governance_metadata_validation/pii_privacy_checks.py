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


def effective_requires_mask(data_subject_types: Iterable[str]) -> bool:
    return "customer" in set(data_subject_types)


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
        entities.append(
            (
                build_id_entity(database_name, table_name, column_name),
                column_name,
                privacy,
            )
        )
        for json_entry in privacy.get("jsonPaths") or []:
            if not isinstance(json_entry, dict):
                continue
            path = json_entry.get("path", "")
            normalized = path if path.startswith("$.") else f"$.{path}"
            entities.append(
                (
                    build_json_path_id_entity(
                        database_name, table_name, column_name, path
                    ),
                    f"{column_name}#{normalized}",
                    json_entry,
                )
            )
    return entities


def validate_privacy_schema(
    privacy: Dict[str, Any],
    catalog_types: Set[str],
    context: str,
    *,
    column_level: bool = False,
) -> List[str]:
    errors: List[str] = []
    pii_type = privacy.get("piiType")
    subjects = privacy.get("dataSubjectType")
    json_paths = privacy.get("jsonPaths") or []

    if column_level:
        has_scalar = bool(pii_type and subjects)
        has_json = bool(json_paths)
        if not has_scalar and not has_json:
            errors.append(
                f"{context}: privacy must set piiType and dataSubjectType, "
                "or at least one jsonPaths entry"
            )
        if pii_type and not subjects:
            errors.append(
                f"{context}: privacy.dataSubjectType is required when piiType is set"
            )
        if subjects and not pii_type and not json_paths:
            errors.append(
                f"{context}: privacy.piiType is required when dataSubjectType is set"
            )
    else:
        if not pii_type:
            errors.append(f"{context}: privacy.piiType is required")
        if not subjects:
            errors.append(
                f"{context}: privacy.dataSubjectType must be a non-empty list"
            )

    if pii_type and pii_type not in catalog_types:
        errors.append(
            f"{context}: privacy.piiType '{pii_type}' is not in pii_catalog.yml"
        )

    if subjects:
        invalid = [s for s in subjects if s not in ALLOWED_DATA_SUBJECT_TYPES]
        if invalid:
            errors.append(
                f"{context}: invalid dataSubjectType {invalid}; "
                f"allowed: {sorted(ALLOWED_DATA_SUBJECT_TYPES)}"
            )

    seen_paths: Set[str] = set()
    for index, json_entry in enumerate(json_paths):
        if not isinstance(json_entry, dict):
            errors.append(f"{context}: jsonPaths[{index}] must be a mapping")
            continue
        path = json_entry.get("path")
        if not path:
            errors.append(f"{context}: jsonPaths[{index}].path is required")
            continue
        if path in seen_paths:
            errors.append(f"{context}: duplicate jsonPaths path '{path}'")
        seen_paths.add(path)
        sub_context = f"{context} jsonPaths[{index}]"
        errors.extend(validate_privacy_schema(json_entry, catalog_types, sub_context))

    return errors


def validate_metadata_privacy(
    metadata: Dict[str, Any], catalog_types: Set[str]
) -> List[str]:
    errors: List[str] = []
    columns = metadata.get("columns") or {}
    for column_name, column_def in columns.items():
        if not isinstance(column_def, dict):
            continue
        privacy = column_def.get("privacy")
        if not privacy:
            continue
        context = f"column '{column_name}'"
        errors.extend(
            validate_privacy_schema(privacy, catalog_types, context, column_level=True)
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
