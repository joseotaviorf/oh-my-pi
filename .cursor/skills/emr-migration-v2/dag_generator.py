"""Generate three validation DAGs for EMR migration.

Renders Jinja templates into DAG directories under dags/platform/:
  - migration_twin_{scope_id}/  (Databricks, original queries)
  - migration_emr_{scope_id}/   (EMR, transpiled queries)
  - migration_compare_{scope_id}/ (comparison, triggered by Datasets)

Twin and EMR DAGs follow the core_support_journey pattern:
  DagExecutionContext + attach_job_cluster_engine_to_context
  -> engine auto-detects Databricks vs EMR from cluster.type in the YAML.
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path
from typing import Any, Dict, List

import yaml
from jinja2 import Environment, FileSystemLoader

REPO_ROOT = Path(__file__).resolve().parents[3]
TEMPLATE_DIR = Path(__file__).resolve().parent / "templates"
PLATFORM_DAG_DIR = REPO_ROOT / "dags" / "platform"

_EMR_DEFAULT_CLUSTER_TYPE = "emr_7_12_consolidation_s_memory_cluster"

sys.path.insert(0, str(Path(__file__).resolve().parent))
from models import DagTranspileReport
from s3_paths import (
    emr_dataset_uri,
    run_prefix,
    twin_dataset_uri,
)


def _jinja_env() -> Environment:
    return Environment(
        loader=FileSystemLoader(str(TEMPLATE_DIR)),
        keep_trailing_newline=True,
    )


def _read_source_cluster(domain: str, dag_name: str) -> Dict[str, Any]:
    cluster_path = REPO_ROOT / "dags" / domain / dag_name / f"{dag_name}_cluster.yml"
    if cluster_path.exists():
        with open(cluster_path) as f:
            return yaml.safe_load(f) or {}
    return {}


def _build_twin_cluster_yaml(source_cluster: Dict[str, Any]) -> Dict[str, Any]:
    cluster = source_cluster.get("cluster", {})
    if not cluster.get("type"):
        cluster["type"] = "consolidation_xs_memory_cluster"
    if not cluster.get("databricks_conn_id"):
        cluster["databricks_conn_id"] = "databricks_new_env"
    return {"cluster": cluster}


def _build_emr_cluster_yaml(source_cluster: Dict[str, Any]) -> Dict[str, Any]:
    source_type = source_cluster.get("cluster", {}).get("type", "")
    if source_type.startswith("emr_"):
        emr_type = source_type
    elif source_type.startswith("consolidation_"):
        emr_type = f"emr_7_12_{source_type}"
    else:
        emr_type = _EMR_DEFAULT_CLUSTER_TYPE
    return {"cluster": {"type": emr_type}}


def _get_source_layer(report: DagTranspileReport) -> str:
    if report.tables:
        return report.tables[0].layer
    return "enrich"


def generate_dags(
    report: DagTranspileReport, output_base: Path | None = None
) -> List[str]:
    """Generate the three DAG directories. Returns list of created paths."""
    env = _jinja_env()
    scope = report.scope
    scope_id = scope.scope_id
    run_id = report.run_id
    tables = report.tables_to_validate
    layer = _get_source_layer(report)
    created_paths = []
    out_root = output_base if output_base else PLATFORM_DAG_DIR

    source_cluster = _read_source_cluster(scope.domain, scope.dag_name)

    table_names = [
        t.table_name
        for t in tables
        if Path(t.original_path).exists()
        and ((t.transpiled and t.transpiled.strip()) or not t.needs_transpile)
    ]
    if not table_names:
        raise ValueError(
            f"No valid tables for {scope_id}: all tables have empty SQL "
            f"or missing source files"
        )

    context = {
        "scope_id": scope_id,
        "domain": scope.domain,
        "dag_name": scope.dag_name,
        "run_id": run_id,
        "layer": layer,
        "table_names": table_names,
        "tables": tables,
        "source_cluster": source_cluster,
        "twin_dataset_uri": twin_dataset_uri(scope_id),
        "emr_dataset_uri": emr_dataset_uri(scope_id),
        "run_prefix": run_prefix(run_id),
    }

    dag_specs = [
        ("twin", "twin"),
        ("migration", "emr"),
        ("comparison", "compare"),
    ]
    for template_prefix, id_prefix in dag_specs:
        dag_id = f"migration_{id_prefix}_{scope_id}"
        dag_dir = out_root / dag_id
        dag_dir.mkdir(parents=True, exist_ok=True)

        dag_template = env.get_template(f"{template_prefix}_dag.py.jinja")
        dag_content = dag_template.render(**context)
        dag_file = dag_dir / f"{dag_id}_dag.py"
        dag_file.write_text(dag_content, encoding="utf-8")

        created_paths.append(str(dag_dir))

    twin_dag_id = f"migration_twin_{scope_id}"
    twin_cluster = _build_twin_cluster_yaml(source_cluster)
    twin_cluster_path = out_root / twin_dag_id / f"{twin_dag_id}_cluster.yml"
    twin_cluster_path.write_text(
        yaml.dump(twin_cluster, default_flow_style=False), encoding="utf-8"
    )

    emr_dag_id = f"migration_emr_{scope_id}"
    emr_cluster = _build_emr_cluster_yaml(source_cluster)
    emr_cluster_path = out_root / emr_dag_id / f"{emr_dag_id}_cluster.yml"
    emr_cluster_path.write_text(
        yaml.dump(emr_cluster, default_flow_style=False), encoding="utf-8"
    )

    valid_set = set(table_names)
    emr_dag_dir = out_root / emr_dag_id
    queries_dir = emr_dag_dir / "queries" / "migration"
    queries_dir.mkdir(parents=True, exist_ok=True)
    for t in tables:
        if t.table_name not in valid_set:
            continue
        sql_content = (
            t.transpiled if t.transpiled else Path(t.original_path).read_text()
        )
        sql_file = queries_dir / f"{t.table_name}.sql"
        sql_file.write_text(sql_content, encoding="utf-8")

    twin_dag_dir = out_root / twin_dag_id
    twin_queries_dir = twin_dag_dir / "queries" / layer
    twin_queries_dir.mkdir(parents=True, exist_ok=True)
    for t in tables:
        if t.table_name in valid_set:
            dst = twin_queries_dir / f"{t.table_name}.sql"
            shutil.copy2(str(t.original_path), str(dst))

    manifest = {
        "run_id": run_id,
        "scope_id": scope_id,
        "domain": scope.domain,
        "dag_name": scope.dag_name,
        "tables": table_names,
        "transpiled_count": report.passed,
        "skipped_count": report.skipped,
        "failed_count": report.failed,
    }
    manifest_file = out_root / f"migration_compare_{scope_id}" / "manifest.json"
    manifest_file.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    return created_paths
