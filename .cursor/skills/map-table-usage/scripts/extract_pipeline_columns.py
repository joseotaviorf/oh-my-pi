#!/usr/bin/env python3
"""Extract columns used from a target table in pipeline SQL consumers.

Best-effort static analysis: finds FROM/JOIN bindings to schema.table, collects
alias.column references in a local window. Output is suitable for the report
"Columns used" column.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
from pathlib import Path

import yaml


def _find_consumer_sql_files(repo_root: Path, schema: str, table: str) -> list[Path]:
    pattern = rf"{re.escape(schema)}\.{re.escape(table)}"
    result = subprocess.run(
        ["rg", "-l", pattern, "dags/", "--glob", "*.sql"],
        cwd=repo_root,
        capture_output=True,
        text=True,
    )
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr.strip() or "rg failed")
    return sorted(repo_root / line.strip() for line in result.stdout.splitlines() if line.strip())


def _dag_meta(sql_path: Path, repo_root: Path) -> tuple[str, str, str, str]:
    rel = sql_path.relative_to(repo_root / "dags")
    parts = rel.parts
    squad = parts[0]
    dag = parts[1] if len(parts) > 1 else parts[0]
    if len(parts) >= 5 and parts[2] == "queries":
        layer = parts[3]
        output_table = sql_path.stem
    else:
        layer = parts[2] if len(parts) > 2 and parts[2] != "queries" else ""
        output_table = sql_path.stem
    return dag, squad, layer, output_table


COLUMN_PREFIXES = (
    "sk_", "id_", "uuid_", "ts_", "dt_", "epoch_", "flg_", "is_", "has_", "mod_",
    "nr_", "order_", "country_", "days_",
)


def _is_likely_table_column(name: str) -> bool:
    return any(name.startswith(prefix) for prefix in COLUMN_PREFIXES)


SQL_KEYWORDS = {
    "and", "or", "not", "in", "is", "null", "true", "false", "between", "day", "interval",
    "case", "when", "then", "else", "end", "as", "cast", "coalesce", "distinct", "select",
    "from", "where", "group", "order", "by", "having", "limit", "union", "all", "left",
    "right", "inner", "outer", "join", "on", "over", "partition", "rows", "range",
}


def _columns_from_bare_from(window: str) -> set[str]:
    cols: set[str] = set()
    select_from = re.search(
        r"SELECT\b(?P<body>[\s\S]{0,2500}?)\bFROM\b",
        window,
        re.IGNORECASE,
    )
    if select_from:
        for col in re.findall(r"\b([a-z_][a-z0-9_]*)\b", select_from.group("body"), re.IGNORECASE):
            name = col.lower()
            if name not in SQL_KEYWORDS and _is_likely_table_column(name):
                cols.add(name)
    where_after = re.search(
        r"\bWHERE\b(?P<body>[\s\S]{0,400}?)(?:GROUP|ORDER|UNION|\)|;|$)", window, re.IGNORECASE
    )
    if where_after:
        for col in re.findall(r"\b([a-z_][a-z0-9_]*)\b", where_after.group("body"), re.IGNORECASE):
            name = col.lower()
            if name not in SQL_KEYWORDS and _is_likely_table_column(name):
                cols.add(name)
    return cols


def _binding_alias(match: re.Match[str], table: str) -> str:
    alias_raw = match.group("alias_as") or match.group("alias_bare")
    if not alias_raw or alias_raw.lower() in SQL_KEYWORDS:
        return table
    return alias_raw


def extract_columns_from_sql(text: str, schema: str, table: str) -> list[str]:
    table_ref = rf"{re.escape(schema)}\.{re.escape(table)}"
    binding_re = re.compile(
        rf"(?:FROM|JOIN)\s+{table_ref}(?:\s+AS\s+(?P<alias_as>[a-zA-Z_][a-zA-Z0-9_]*)"
        rf"|\s+(?P<alias_bare>[a-zA-Z_][a-zA-Z0-9_]*))?",
        re.IGNORECASE,
    )
    # alias_cols: from explicit alias.column refs — trust these, skip prefix filter
    # bare_cols:  from bare FROM path — _columns_from_bare_from already prefix-filters
    alias_cols: set[str] = set()
    bare_cols: set[str] = set()

    for match in binding_re.finditer(text):
        alias = _binding_alias(match, table)
        start = max(0, match.start() - 1500)
        end = min(len(text), match.end() + 1200)
        window = text[start:end]
        for col in re.findall(rf"\b{re.escape(alias)}\.([a-z_][a-z0-9_]*)", window, re.IGNORECASE):
            name = col.lower()
            if name not in SQL_KEYWORDS:
                alias_cols.add(name)

    bare_re = re.compile(rf"\bFROM\s+{table_ref}\b", re.IGNORECASE)
    for match in bare_re.finditer(text):
        start = max(0, match.start() - 400)
        end = min(len(text), match.end() + 200)
        bare_cols.update(_columns_from_bare_from(text[start:end]))

    return sorted(alias_cols | bare_cols)


def _declaration_path(dag: str, squad: str, repo_root: Path) -> Path | None:
    direct = repo_root / "dags" / squad / dag / f"{dag}_declaration.yml"
    if direct.exists():
        return direct
    matches = sorted((repo_root / "dags").glob(f"*/{dag}/{dag}_declaration.yml"))
    return matches[0] if matches else None


def _declaration_owner(dag: str, squad: str, repo_root: Path) -> str:
    decl = _declaration_path(dag, squad, repo_root)
    if not decl:
        return ""
    try:
        data = yaml.safe_load(decl.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError:
        return ""
    owner = data.get("dag", {}).get("owner")
    return str(owner).strip() if owner else ""


def _metadata_path(dag: str, squad: str, layer: str, output_table: str, repo_root: Path) -> Path | None:
    direct = repo_root / "dags" / squad / dag / "metadata" / layer / f"{output_table}.yml"
    if direct.exists():
        return direct
    matches = sorted((repo_root / "dags").glob(f"*/{dag}/metadata/{layer}/{output_table}.yml"))
    return matches[0] if matches else None


def _metadata_owner(metadata_path: Path | None) -> str:
    if not metadata_path:
        return ""
    try:
        data = yaml.safe_load(metadata_path.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError:
        return ""
    owner = data.get("owner")
    return str(owner).strip() if owner else ""


def _output_table_owner(dag: str, squad: str, layer: str, output_table: str, repo_root: Path) -> str:
    return _metadata_owner(_metadata_path(dag, squad, layer, output_table, repo_root))


def target_table_metadata(schema: str, table: str, repo_root: Path) -> tuple[str, str]:
    """Return (owner, producer_dag) from metadata YAML of the target table."""
    for path in sorted((repo_root / "dags").glob(f"**/metadata/**/{table}.yml")):
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except yaml.YAMLError:
            continue
        database_name = str(data.get("database_name", "")).strip()
        if database_name and database_name != schema:
            continue
        owner = str(data.get("owner", "")).strip()
        if not owner:
            continue
        parts = path.parts
        dag = parts[parts.index("dags") + 2] if "dags" in parts else ""
        return owner, dag
    return "", ""


def analyze_file(sql_path: Path, repo_root: Path, schema: str, table: str) -> dict[str, str]:
    text = sql_path.read_text(encoding="utf-8")
    dag, squad, layer, output_table = _dag_meta(sql_path, repo_root)
    columns = extract_columns_from_sql(text, schema, table)
    return {
        "dag": dag,
        "squad": squad,
        "dag_owner": _declaration_owner(dag, squad, repo_root),
        "output_table_owner": _output_table_owner(dag, squad, layer, output_table, repo_root),
        "layer": layer,
        "output_table": output_table,
        "sql_path": str(sql_path.relative_to(repo_root)),
        "columns_used": ", ".join(columns) if columns else "(none detected — review manually)",
        "column_count": len(columns),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema", required=True)
    parser.add_argument("--table", required=True)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[4])
    parser.add_argument("--output", type=Path, help="Write JSON or CSV (by suffix)")
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    producer_owner, producer_dag = target_table_metadata(args.schema, args.table, repo_root)
    rows = [
        {
            **analyze_file(path, repo_root, args.schema, args.table),
            "producer_owner": producer_owner,
            "producer_dag": producer_dag,
        }
        for path in _find_consumer_sql_files(repo_root, args.schema, args.table)
    ]

    for row in rows:
        print(
            f"{row['dag']}\t{row['layer']}/{row['output_table']}\t"
            f"{row['column_count']} cols\t{row['columns_used'][:120]}..."
            if len(row["columns_used"]) > 120
            else f"{row['dag']}\t{row['layer']}/{row['output_table']}\t{row['column_count']} cols\t{row['columns_used']}"
        )

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        if args.output.suffix.lower() == ".csv":
            with args.output.open("w", newline="", encoding="utf-8") as fh:
                fieldnames = [
                    "dag",
                    "squad",
                    "dag_owner",
                    "output_table_owner",
                    "layer",
                    "output_table",
                    "sql_path",
                    "columns_used",
                    "column_count",
                    "producer_owner",
                    "producer_dag",
                ]
                writer = csv.DictWriter(fh, fieldnames=fieldnames)
                writer.writeheader()
                writer.writerows(rows)
        else:
            args.output.write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
