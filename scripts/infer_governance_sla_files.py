# /// script
# requires-python = ">=3.12"
# dependencies = ["pyyaml"]
# ///

"""Infer sla/<layer>/<table>.yml for governance DAGs with profiling enabled."""

from __future__ import annotations

import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[1]
DAGS = REPO / "dags" / "governance"
PARTITION_COLS = {"year", "month", "day"}
# Tables with profiling but no partition-empty SLA (upsert / domain opt-out).
SKIP_SLA_TABLES = frozenset({"fairness_classification"})


def list_targets() -> list[dict]:
    rows: list[dict] = []
    for decl_path in sorted(DAGS.glob("**/*_declaration.yml")):
        content = yaml.safe_load(decl_path.read_text()) or {}
        wf = content.get("workflow") or {}
        obs = wf.get("observability") or {}
        if obs.get("enabled") is not True:
            continue
        dag = content.get("dag") or {}
        layer = wf.get("layer", "enrich")
        default_partitions = set(wf.get("default_partitions") or [])
        tables_custom = wf.get("tables_customization") or {}
        dag_folder = decl_path.parent

        table_names: set[str] = set(tables_custom)
        queries_dir = dag_folder / "queries" / layer
        if queries_dir.is_dir():
            table_names.update(p.stem for p in queries_dir.glob("*.sql"))

        for table in sorted(table_names):
            if table in SKIP_SLA_TABLES:
                continue
            meta_path = dag_folder / "metadata" / layer / f"{table}.yml"
            if not meta_path.exists():
                continue
            meta = yaml.safe_load(meta_path.read_text()) or {}
            database_name = meta.get("database_name")
            if not database_name:
                continue
            tc = tables_custom.get(table) or {}
            if "partitions" in tc:
                parts = set(tc["partitions"] or [])
            else:
                parts = set(default_partitions or [])
            if not PARTITION_COLS.issubset(parts):
                continue
            sla_path = dag_folder / "sla" / layer / f"{table}.yml"
            if sla_path.exists():
                continue
            rows.append(
                {
                    "database_name": database_name,
                    "table": table,
                    "sla_path": sla_path,
                }
            )
    return rows


def build_sla(target: dict) -> dict:
    return {
        "database_name": target["database_name"],
        "table_name": target["table"],
        "checks": [{"type": "empty_partition"}],
    }


def render_yaml(content: dict) -> str:
    return yaml.safe_dump(content, sort_keys=False, allow_unicode=True)


def main() -> int:
    targets = list_targets()
    print(f"Generating SLA files for {len(targets)} tables...")
    created = 0
    for target in targets:
        print(f"  write {target['database_name']}.{target['table']} ...", flush=True)
        content = build_sla(target)
        target["sla_path"].parent.mkdir(parents=True, exist_ok=True)
        target["sla_path"].write_text(render_yaml(content), encoding="utf-8")
        created += 1
    print(f"Created {created} SLA file(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
