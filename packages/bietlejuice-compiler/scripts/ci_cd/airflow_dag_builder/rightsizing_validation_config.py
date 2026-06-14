"""
Build minimal validation: blocks for cluster rightsizing recommendations.

Shares preset-diff logic with cluster_validation_mapping.py and YAML formatting
with extract_cluster_validation_files.py / cluster_yaml_format.py.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Protocol

import yaml
from quintoandar_logger import QuintoAndarLogger

from .cluster_validation_mapping import (
    ValidationClusterSpec,
    build_rightsizing_validation_cluster_spec,
    is_emr_prod_cluster_args,
)
from .cluster_yaml_format import dump_cluster_yaml

REPO_ROOT = Path(__file__).resolve().parents[5]
DEFAULT_DAGS_ROOT = REPO_ROOT / "dags"
LOGGER = QuintoAndarLogger("rightsizing_validation_config")

_ACTIONABLE_COHORTS = frozenset(
    {
        "collapse_to_single",
        "right_size_multi",
        "downsize_workers",
        "driver_downsize",
        "protect_oom_risk",
        "right_size_to_memory_family",
        "keep_multi_sla",
        "keep_multi_memory",
        "keep_multi_compute",
        "keep_multi_balanced",
        "keep_multi_cost",
        "keep_multi_io_bound",
        "healthy_single",
        "expand_to_multi",
    }
)

_NORMALIZATION_ACTIONS = frozenset({"disable_photon", "drop_nvme"})

_KEEP_MULTI_COHORTS = frozenset(
    {
        "keep_multi_sla",
        "keep_multi_memory",
        "keep_multi_compute",
        "keep_multi_balanced",
        "keep_multi_cost",
        "keep_multi_io_bound",
    }
)

_CLUSTER_FILE_TOP_LEVEL_KEYS = frozenset(
    {"dag", "workflow", "cluster", "validation", "spark_session_configs"}
)


class RightsizingRecommendation(Protocol):
    """Subset of recommend_cluster_specs.Recommendation used for validation YAML."""

    dag_id: str
    cohort: str
    confidence: str
    actions: str
    current_preset: str | None
    recommended_preset: str | None
    rec_driver_node_type: str | None
    rec_worker_node_type: str | None
    rec_worker_count: int | None
    num_workers_override: int | None
    driver_override_node_type_id: str | None
    rec_runtime_engine: str | None
    driver_action: str | None
    worker_action: str | None
    projected: Any


def find_dag_cluster_path(
    dag_name: str, dags_root: Path = DEFAULT_DAGS_ROOT
) -> Path | None:
    """Find *_cluster.yml for a dag_name by searching dags/ tree."""
    target = f"{dag_name}_cluster.yml"
    matches = list(dags_root.rglob(target))
    return matches[0] if len(matches) == 1 else None


def find_dag_folder(dag_name: str, dags_root: Path = DEFAULT_DAGS_ROOT) -> Path | None:
    """Find the DAG folder containing {dag_name}_declaration.yml."""
    target = f"{dag_name}_declaration.yml"
    matches = list(dags_root.rglob(target))
    return matches[0].parent if len(matches) == 1 else None


def load_declaration(dag_name: str, dags_root: Path) -> dict | None:
    folder = find_dag_folder(dag_name, dags_root)
    if not folder:
        return None
    decl_path = folder / f"{dag_name}_declaration.yml"
    if not decl_path.exists():
        return None
    try:
        doc = yaml.safe_load(decl_path.read_text(encoding="utf-8"))
        return doc if isinstance(doc, dict) else None
    except (OSError, yaml.YAMLError) as exc:
        LOGGER.warning("Failed to parse YAML %s: %s", decl_path, exc)
        return None


def load_prod_cluster_args(dag_name: str, dags_root: Path) -> dict | None:
    """Read prod cluster args from *_cluster.yml, falling back to declaration."""
    cluster_path = find_dag_cluster_path(dag_name, dags_root)
    if cluster_path and cluster_path.exists():
        try:
            doc = yaml.safe_load(cluster_path.read_text(encoding="utf-8")) or {}
            cluster = doc.get("cluster") if isinstance(doc, dict) else None
            if isinstance(cluster, dict):
                return cluster
        except (OSError, yaml.YAMLError) as exc:
            LOGGER.warning("Failed to parse YAML %s: %s", cluster_path, exc)

    declaration = load_declaration(dag_name, dags_root)
    if declaration:
        cluster = declaration.get("cluster")
        if isinstance(cluster, dict):
            return cluster
    return None


def get_current_cluster_type(dag_name: str, dags_root: Path) -> str | None:
    """Read prod cluster.type from *_cluster.yml, falling back to declaration."""
    cluster_path = find_dag_cluster_path(dag_name, dags_root)
    if cluster_path and cluster_path.exists():
        try:
            doc = yaml.safe_load(cluster_path.read_text(encoding="utf-8")) or {}
            cluster_type = (
                doc.get("cluster", {}).get("type") if isinstance(doc, dict) else None
            )
            if cluster_type:
                return cluster_type
        except (OSError, yaml.YAMLError) as exc:
            LOGGER.warning("Failed to parse YAML %s: %s", cluster_path, exc)
    folder = find_dag_folder(dag_name, dags_root)
    if not folder:
        return None
    decl_path = folder / f"{dag_name}_declaration.yml"
    if not decl_path.exists():
        return None
    try:
        doc = yaml.safe_load(decl_path.read_text(encoding="utf-8"))
        return doc.get("cluster", {}).get("type") if isinstance(doc, dict) else None
    except (OSError, yaml.YAMLError) as exc:
        LOGGER.warning("Failed to parse YAML %s: %s", decl_path, exc)
        return None


def validation_cluster_dict_from_spec(spec: ValidationClusterSpec) -> dict[str, Any]:
    """Convert ValidationClusterSpec to validation.cluster dict."""
    val_cluster: dict[str, Any] = {"type": spec.cluster_type}
    if spec.databricks_conn_id is not None:
        val_cluster["databricks_conn_id"] = spec.databricks_conn_id
    if spec.access_control_list is not None:
        val_cluster["access_control_list"] = spec.access_control_list
    if spec.custom_libraries is not None:
        val_cluster["custom_libraries"] = spec.custom_libraries
    if spec.custom_configurations:
        val_cluster["custom_configurations"] = spec.custom_configurations
    return val_cluster


def generate_validation_config(
    rec: RightsizingRecommendation,
    databricks_conn_id: str = "databricks_new",
    *,
    dags_root: Path = DEFAULT_DAGS_ROOT,
) -> dict | None:
    """Return a minimal validation block dict, or None when not actionable."""
    if rec.cohort not in _ACTIONABLE_COHORTS or not rec.recommended_preset:
        return None
    if rec.cohort in _KEEP_MULTI_COHORTS:
        accepted_actions = {
            "reduce_driver",
            "reduce_worker_type",
            "reduce_worker_count",
        }
        if not accepted_actions.intersection(rec.actions.split("|")):
            return None

    dag_name = rec.dag_id.removeprefix("bietlejuice.")
    prod_type = get_current_cluster_type(dag_name, dags_root) or rec.current_preset
    has_normalization = bool(
        getattr(rec, "rec_runtime_engine", None)
        or _NORMALIZATION_ACTIONS.intersection(rec.actions.split("|"))
    )
    has_worker_count_override = getattr(rec, "num_workers_override", None) is not None
    if (
        prod_type
        and rec.recommended_preset == prod_type
        and not has_normalization
        and not has_worker_count_override
    ):
        return None

    prod_cluster_args = load_prod_cluster_args(dag_name, dags_root)
    if not prod_cluster_args:
        prod_cluster_args = {"type": prod_type or rec.current_preset or "unknown"}
    if is_emr_prod_cluster_args(prod_cluster_args):
        return None

    declaration = load_declaration(dag_name, dags_root) or {}

    spec = build_rightsizing_validation_cluster_spec(
        prod_cluster_args=prod_cluster_args,
        declaration=declaration,
        recommended_preset=rec.recommended_preset,
        recommended_num_workers=rec.num_workers_override or rec.rec_worker_count,
        recommended_driver_node_type=(
            rec.driver_override_node_type_id or rec.rec_driver_node_type
        ),
        recommended_worker_node_type=rec.rec_worker_node_type,
        recommended_runtime_engine=getattr(rec, "rec_runtime_engine", None),
        databricks_conn_id_fallback=databricks_conn_id,
    )
    if spec is None:
        return None

    validation_block: dict[str, Any] = {
        "cluster": validation_cluster_dict_from_spec(spec),
    }
    if spec.allow_custom_spark_job:
        validation_block["allow_custom_spark_job"] = True

    projected = rec.projected
    return {
        "dag_id": rec.dag_id,
        "cohort": rec.cohort,
        "confidence": rec.confidence,
        "actions": rec.actions,
        "est_cost_delta_pct": getattr(projected, "est_cost_delta_pct", None),
        "driver_action": rec.driver_action,
        "worker_action": rec.worker_action,
        "blocking_reason": getattr(projected, "blocking_reason", None),
        "validation": validation_block,
    }


def _extract_top_level_section_text(text: str, section_key: str) -> str | None:
    """Return verbatim top-level section block including trailing newline."""
    prefix = f"{section_key}:"
    lines = text.splitlines(keepends=True)
    start_idx: int | None = None
    for index, line in enumerate(lines):
        if line.startswith(prefix):
            start_idx = index
            break
    if start_idx is None:
        return None

    end_idx = len(lines)
    for index in range(start_idx + 1, len(lines)):
        stripped = lines[index].strip()
        if not stripped or stripped.startswith("#"):
            continue
        key = lines[index].split(":", 1)[0]
        if key in _CLUSTER_FILE_TOP_LEVEL_KEYS and not lines[index].startswith(" "):
            end_idx = index
            break

    block = "".join(lines[start_idx:end_idx])
    if not block.endswith("\n"):
        block += "\n"
    return block


def format_validation_section_yaml(validation_doc: dict) -> str:
    """Format validation: block (matches extract_cluster_validation_files.py)."""
    dumped = dump_cluster_yaml(validation_doc)
    lines = ["validation:"]
    for line in dumped.splitlines():
        if line.strip():
            lines.append(f"  {line}")
    return "\n".join(lines) + "\n"


def _normalize_cluster_file_text(text: str) -> str:
    return text.rstrip("\n") + "\n"


def remove_validation_from_cluster_file(cluster_path: Path) -> bool:
    """Drop a stale validation: section. Returns True when the file changed."""
    if not cluster_path.exists():
        return False
    original_text = cluster_path.read_text(encoding="utf-8")
    validation_text = _extract_top_level_section_text(original_text, "validation")
    if validation_text is None:
        return False

    new_text = original_text.replace(validation_text, "")
    while "\n\n\n" in new_text:
        new_text = new_text.replace("\n\n\n", "\n\n")
    cluster_path.write_text(
        _normalize_cluster_file_text(new_text.rstrip("\n") + "\n"),
        encoding="utf-8",
    )
    return True


def write_validation_cluster_file(
    cluster_path: Path,
    val_config: dict,
    current_cluster_type: str | None,
    databricks_conn_id: str = "databricks_new",
) -> None:
    """Upsert the validation: section in a *_cluster.yml file."""
    validation_doc = val_config["validation"]
    tail_sections: list[str] = []

    if cluster_path.exists():
        original_text = cluster_path.read_text(encoding="utf-8")
        cluster_text = _extract_top_level_section_text(original_text, "cluster")
        if cluster_text is None:
            LOGGER.warning(
                "No cluster: section in %s; creating minimal cluster block",
                cluster_path,
            )
            cluster_text = dump_cluster_yaml(
                {
                    "cluster": {
                        "type": current_cluster_type or "unknown",
                        "databricks_conn_id": databricks_conn_id,
                    }
                }
            )
        prod_block = cluster_text.rstrip("\n")
        for key in ("spark_session_configs",):
            section = _extract_top_level_section_text(original_text, key)
            if section:
                tail_sections.append(section.rstrip("\n"))
    else:
        if current_cluster_type:
            prod_block = dump_cluster_yaml(
                {
                    "cluster": {
                        "type": current_cluster_type,
                        "databricks_conn_id": databricks_conn_id,
                    }
                }
            ).rstrip("\n")
        else:
            prod_block = ""

    content = prod_block + "\n" + format_validation_section_yaml(validation_doc)
    if tail_sections:
        content += "\n".join(tail_sections) + "\n"

    cluster_path.parent.mkdir(parents=True, exist_ok=True)
    cluster_path.write_text(
        _normalize_cluster_file_text(content),
        encoding="utf-8",
    )


def write_validation_configs(
    recs: list[RightsizingRecommendation],
    out_yaml: Path,
    *,
    dags_root: Path = DEFAULT_DAGS_ROOT,
    write_cluster_files: bool = False,
    databricks_conn_id: str = "databricks_new",
) -> int:
    """Write validation_configs.yml and optionally update *_cluster.yml files."""
    entries: list[dict] = []
    for rec in recs:
        dag_name = rec.dag_id.removeprefix("bietlejuice.")
        prod_cluster_args = load_prod_cluster_args(dag_name, dags_root)
        if prod_cluster_args and is_emr_prod_cluster_args(prod_cluster_args):
            if write_cluster_files:
                cluster_path = find_dag_cluster_path(dag_name, dags_root)
                if cluster_path is None:
                    folder = find_dag_folder(dag_name, dags_root)
                    if folder:
                        cluster_path = folder / f"{dag_name}_cluster.yml"
                if cluster_path is not None:
                    remove_validation_from_cluster_file(cluster_path)
            continue

        cfg = generate_validation_config(rec, databricks_conn_id, dags_root=dags_root)
        if not cfg:
            continue
        entries.append(cfg)

        if write_cluster_files:
            cluster_path = find_dag_cluster_path(dag_name, dags_root)
            if cluster_path is None:
                folder = find_dag_folder(dag_name, dags_root)
                if folder:
                    cluster_path = folder / f"{dag_name}_cluster.yml"
            if cluster_path is None:
                LOGGER.warning("cannot locate cluster file for %s", rec.dag_id)
                continue
            current_type = get_current_cluster_type(dag_name, dags_root)
            write_validation_cluster_file(
                cluster_path, cfg, current_type, databricks_conn_id
            )

    out_yaml.parent.mkdir(parents=True, exist_ok=True)
    out_yaml.write_text(
        yaml.dump(
            entries, default_flow_style=False, allow_unicode=True, sort_keys=False
        ),
        encoding="utf-8",
    )
    return len(entries)
