"""DAG path scope for People conventions CI.

Covers ``dags/people/**`` and ``dags/enterprise_efficiency/**``. Shared path
helpers keep pairing and convention validators aligned on which folders and
layers participate in guard rails.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

DOMAIN_FOLDER_NAMES: Tuple[str, ...] = ("people", "enterprise_efficiency")
DQ_REQUIRED_LAYERS = frozenset({"clean", "enrich", "dw", "metric"})
SCOPE_PATHS_HELP = "dags/people/ or dags/enterprise_efficiency/"

_QUERIES_LAYER_RE = re.compile(r"/queries/(?P<layer>[^/]+)/")
_METADATA_LAYER_RE = re.compile(r"/metadata/(?P<layer>[^/]+)/")


def normalize_path(path: str) -> str:
    """Normalize filesystem separators to forward slashes for stable comparisons."""
    return path.replace("\\", "/")


def scoped_domain_roots() -> Tuple[str, ...]:
    """Return repo-relative roots for every domain folder in this CI scope."""
    return tuple(f"dags/{name}" for name in DOMAIN_FOLDER_NAMES)


def is_scoped_domain_path(path: str) -> bool:
    """Return True when ``path`` lies under a scoped domain root or is the root itself."""
    normalized = normalize_path(path)
    if normalized in scoped_domain_roots():
        return True
    return any(normalized.startswith(f"dags/{name}/") for name in DOMAIN_FOLDER_NAMES)


def domain_folder_from_parts(parts: Sequence[str]) -> Optional[str]:
    """Extract the domain folder name (``people`` or ``enterprise_efficiency``) from path parts."""
    try:
        dags_idx = parts.index("dags")
        if dags_idx + 1 < len(parts):
            folder = parts[dags_idx + 1]
            if folder in DOMAIN_FOLDER_NAMES:
                return folder
    except ValueError:
        pass
    return None


def domain_root_from_parts(parts: Sequence[str]) -> Optional[str]:
    """Return ``dags/<domain>`` when the path parts identify a scoped domain."""
    folder = domain_folder_from_parts(parts)
    if folder:
        return f"dags/{folder}"
    return None


def dag_folder_from_path(path: Path | str) -> Optional[str]:
    """Return the DAG package folder immediately under the scoped domain (e.g. ``pin``)."""
    normalized = normalize_path(str(path))
    parts = normalized.split("/")
    try:
        dags_idx = parts.index("dags")
        domain_folder = domain_folder_from_parts(parts)
        if domain_folder is None:
            return None
        domain_idx = parts.index(domain_folder, dags_idx)
        if domain_idx + 1 < len(parts):
            return parts[domain_idx + 1]
    except ValueError:
        pass
    return None


def layer_from_artifact(path: str) -> Optional[str]:
    """Read the pipeline layer from a ``queries/`` or ``metadata/`` artifact path."""
    normalized = normalize_path(path)
    match = _QUERIES_LAYER_RE.search(normalized)
    if match:
        return match.group("layer")
    match = _METADATA_LAYER_RE.search(normalized)
    if match:
        return match.group("layer")
    return None


def requires_dq_file(path: str) -> bool:
    """Return True when a query/metadata artifact must have a sibling ``data_quality`` YAML.

    Raw and reverse layers are excluded because they are either ingestion buffers
    or export-only surfaces without the same Inmetro monitoring contract.
    """
    if not is_scoped_domain_path(path):
        return False
    layer = layer_from_artifact(path)
    return layer in DQ_REQUIRED_LAYERS


def _artifact_segments(
    artifact_path: str,
) -> Optional[Tuple[str, Tuple[str, ...], str, str]]:
    """Parse a query or metadata path into ``(domain_root, dag_parts, layer, table)``."""
    normalized = normalize_path(artifact_path)
    parts = Path(normalized).parts
    domain_root = domain_root_from_parts(parts)
    if domain_root is None:
        return None
    try:
        dags_idx = parts.index("dags")
        domain_folder = parts[dags_idx + 1]
        domain_idx = parts.index(domain_folder, dags_idx)
        if "queries" in parts:
            folder_idx = parts.index("queries", domain_idx)
            layer = parts[folder_idx + 1]
            table = Path(artifact_path).stem
            dag_parts = parts[domain_idx + 1 : folder_idx]
        elif "metadata" in parts:
            folder_idx = parts.index("metadata", domain_idx)
            layer = parts[folder_idx + 1]
            table = Path(artifact_path).stem
            dag_parts = parts[domain_idx + 1 : folder_idx]
        else:
            return None
        if layer not in DQ_REQUIRED_LAYERS:
            return None
        return domain_root, tuple(dag_parts), layer, table
    except (ValueError, IndexError):
        return None


def dq_path_for_artifact(artifact_path: str) -> Optional[Path]:
    """Map a query or metadata file to its expected ``data_quality/{layer}/{table}.yml``."""
    parsed = _artifact_segments(artifact_path)
    if parsed is None:
        return None
    domain_root, dag_parts, layer, table = parsed
    return Path(domain_root).joinpath(*dag_parts, "data_quality", layer, f"{table}.yml")


def dq_path_for_sql(sql_path: Path) -> Optional[Path]:
    """Return the ``data_quality`` YAML path paired with a query SQL file."""
    return dq_path_for_artifact(str(sql_path))


def metadata_path_for_sql(sql_path: Path) -> Optional[Path]:
    """Return the ``metadata`` YAML path paired with a query SQL file."""
    normalized = normalize_path(str(sql_path))
    parts = Path(normalized).parts
    domain_root = domain_root_from_parts(parts)
    if domain_root is None:
        return None
    try:
        dags_idx = parts.index("dags")
        domain_folder = parts[dags_idx + 1]
        domain_idx = parts.index(domain_folder, dags_idx)
        queries_idx = parts.index("queries", domain_idx)
        layer = parts[queries_idx + 1]
        table = sql_path.stem
        dag_parts = parts[domain_idx + 1 : queries_idx]
        return Path(domain_root).joinpath(*dag_parts, "metadata", layer, f"{table}.yml")
    except (ValueError, IndexError):
        return None


def dq_path_for_metadata(meta_path: Path) -> Optional[Path]:
    """Return the ``data_quality`` YAML path paired with a metadata file."""
    normalized = normalize_path(str(meta_path))
    parts = Path(normalized).parts
    domain_root = domain_root_from_parts(parts)
    if domain_root is None:
        return None
    try:
        dags_idx = parts.index("dags")
        domain_folder = parts[dags_idx + 1]
        domain_idx = parts.index(domain_folder, dags_idx)
        metadata_idx = parts.index("metadata", domain_idx)
        layer = parts[metadata_idx + 1]
        if layer not in DQ_REQUIRED_LAYERS:
            return None
        table = meta_path.stem
        dag_parts = parts[domain_idx + 1 : metadata_idx]
        return Path(domain_root).joinpath(
            *dag_parts, "data_quality", layer, f"{table}.yml"
        )
    except (ValueError, IndexError):
        return None


def iter_scoped_domain_roots() -> List[Path]:
    """Yield ``Path`` objects for each scoped domain root (for full-repo walks)."""
    return [Path(root) for root in scoped_domain_roots()]


def expand_scoped_paths(raw_paths: Sequence[str]) -> List[Path]:
    """Expand CLI ``--paths`` arguments to files under scoped domains.

    Raises ``SystemExit`` when a path is outside scope or does not exist, so local
    runs fail fast instead of silently skipping wrong folders.
    """
    files: List[Path] = []
    for raw in raw_paths:
        path = Path(raw)
        if not is_scoped_domain_path(str(path).replace("\\", "/")):
            raise SystemExit(f"error: --paths must be under {SCOPE_PATHS_HELP}: {raw}")
        if path.is_dir():
            files.extend(sorted(path.rglob("*")))
        elif path.is_file():
            files.append(path)
        else:
            raise SystemExit(f"error: --paths target does not exist: {raw}")
    return [p for p in files if p.is_file()]
