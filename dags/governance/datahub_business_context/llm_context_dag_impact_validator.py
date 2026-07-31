"""Detect golden-query breakage when DAG metadata YAML changes."""

from __future__ import annotations

import re
import subprocess
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import yaml
from golden_query_metadata_validator import _columns_from_metadata
from golden_query_schema_validator import (
    _grep_column_mentions,
    column_refs_for_table_in_sql,
    table_refs_in_sql,
)

_REPO_ROOT = Path(__file__).resolve().parents[3]
_BUSINESS_DIR = _REPO_ROOT / "docs/llm_context/business_entities"
_METRIC_DIR = _REPO_ROOT / "docs/llm_context/metric_entities"

_DAG_METADATA_RE = re.compile(
    r"^dags/(?P<domain>[^/]+)/(?P<dag>[^/]+)/metadata/(?P<layer>[^/]+)/(?P<table>[^/]+)\.yml$"
)


@dataclass(frozen=True)
class GoldenQueryRef:
    doc_path: Path
    query_label: str
    sql: str


@dataclass(frozen=True)
class TableImpact:
    schema: str
    table: str
    metadata_path: str
    removed_columns: frozenset[str]
    added_columns: frozenset[str]
    metadata_deleted: bool


def _rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(_REPO_ROOT))
    except ValueError:
        return str(path)


def _all_entity_files() -> list[Path]:
    found: list[Path] = []
    for directory in (_BUSINESS_DIR, _METRIC_DIR):
        if directory.is_dir():
            found.extend(
                p for p in directory.glob("*.md") if not p.name.startswith("_")
            )
    return sorted(found, key=str)


def _is_dag_metadata(rel_path: str) -> bool:
    return bool(_DAG_METADATA_RE.match(rel_path))


def filter_dag_impact_paths(paths: Iterable[str | Path]) -> list[str]:
    """Keep repo-relative DAG metadata YAML paths relevant to this gate."""
    out: list[str] = []
    for raw in paths:
        rel = str(raw).strip().replace("\\", "/")
        if rel.startswith("./"):
            rel = rel[2:]
        if _is_dag_metadata(rel):
            out.append(rel)
    return sorted(set(out))


def _table_from_metadata_yaml(content: str) -> tuple[str, str] | None:
    try:
        metadata = yaml.safe_load(content) or {}
    except yaml.YAMLError:
        return None
    database_name = str(metadata.get("database_name") or "").strip()
    table_name = str(metadata.get("table_name") or "").strip()
    if not database_name or not table_name:
        return None
    return database_name.lower(), table_name.lower()


def git_file_at_ref(
    rel_path: str, from_ref: str, *, repo_root: Path | None = None
) -> str | None:
    root = (repo_root or _REPO_ROOT).resolve()
    result = subprocess.run(
        ["git", "show", f"{from_ref}:{rel_path}"],
        capture_output=True,
        text=True,
        cwd=root,
    )
    if result.returncode != 0:
        return None
    return result.stdout


def diff_metadata_columns(
    rel_path: str,
    from_ref: str,
    *,
    repo_root: Path | None = None,
) -> tuple[set[str], set[str], bool]:
    """Return ``(removed, added, metadata_deleted)`` for one metadata YAML path."""
    root = (repo_root or _REPO_ROOT).resolve()
    old_content = git_file_at_ref(rel_path, from_ref, repo_root=root)
    new_path = root / rel_path
    new_content = new_path.read_text(encoding="utf-8") if new_path.is_file() else None

    old_cols = (
        _columns_from_metadata(yaml.safe_load(old_content) or {})
        if old_content
        else set()
    )
    new_cols = (
        _columns_from_metadata(yaml.safe_load(new_content) or {})
        if new_content
        else set()
    )
    removed = old_cols - new_cols
    added = new_cols - old_cols
    metadata_deleted = old_content is not None and new_content is None
    return removed, added, metadata_deleted


def build_golden_query_index(
    entity_files: list[Path] | None = None,
) -> dict[tuple[str, str], list[GoldenQueryRef]]:
    """Map ``(schema, table)`` to golden queries that reference the table."""
    from sync.document_parser import parse_entity_markdown
    from sync.markdown_sanitizer import sanitize_uploaded_markdown

    index: dict[tuple[str, str], list[GoldenQueryRef]] = defaultdict(list)
    for md_path in entity_files or _all_entity_files():
        try:
            content = md_path.read_text(encoding="utf-8")
        except OSError:
            continue
        parsed = parse_entity_markdown(
            content,
            unescape=False,
            sanitize_fn=sanitize_uploaded_markdown,
        )
        for idx, gq in enumerate(parsed.golden_queries, start=1):
            sql = (gq.sql or "").strip()
            if not sql:
                continue
            label = gq.name or f"Query {idx}"
            for schema, table in table_refs_in_sql(sql):
                key = (schema.lower(), table.lower())
                index[key].append(GoldenQueryRef(md_path, label, sql))
    return dict(index)


def collect_table_impacts(
    changed_paths: list[str],
    from_ref: str,
    *,
    repo_root: Path | None = None,
) -> list[TableImpact]:
    """Derive per-table column deltas from changed DAG metadata YAML paths."""
    impacts: list[TableImpact] = []
    for meta_rel in sorted(set(changed_paths)):
        removed, added, metadata_deleted = diff_metadata_columns(
            meta_rel, from_ref, repo_root=repo_root
        )
        if not removed and not added and not metadata_deleted:
            continue

        root = (repo_root or _REPO_ROOT).resolve()
        current_path = root / meta_rel
        content: str | None
        if current_path.is_file():
            content = current_path.read_text(encoding="utf-8")
        else:
            content = git_file_at_ref(meta_rel, from_ref, repo_root=root)

        if not content:
            continue
        table_key = _table_from_metadata_yaml(content)
        if table_key is None:
            continue

        impacts.append(
            TableImpact(
                schema=table_key[0],
                table=table_key[1],
                metadata_path=meta_rel,
                removed_columns=frozenset(removed),
                added_columns=frozenset(added),
                metadata_deleted=metadata_deleted,
            )
        )
    return impacts


def validate_table_impacts(
    impacts: list[TableImpact],
    golden_query_index: dict[tuple[str, str], list[GoldenQueryRef]],
) -> tuple[list[str], list[str]]:
    """Return blocking errors and non-blocking warnings."""
    errors: list[str] = []
    warnings: list[str] = []
    warned_tables: set[tuple[str, str]] = set()

    for impact in impacts:
        table_key = (impact.schema, impact.table)
        refs = golden_query_index.get(table_key, [])
        if not refs:
            continue

        fqn = f"`{impact.schema}.{impact.table}`"
        docs = ", ".join(sorted({_rel(r.doc_path) for r in refs}))

        if impact.metadata_deleted:
            errors.append(
                f"Metadata removed for {fqn} ({impact.metadata_path}) but golden "
                f"queries still reference it in: {docs}"
            )
            continue

        before_columns = set(impact.removed_columns) | set(impact.added_columns)
        # Reconstruct the pre-change column set for unqualified reference resolution.
        current_path = _REPO_ROOT / impact.metadata_path
        if current_path.is_file():
            current_cols = _columns_from_metadata(
                yaml.safe_load(current_path.read_text(encoding="utf-8")) or {}
            )
            before_columns = current_cols | set(impact.removed_columns)

        if impact.removed_columns:
            for ref in refs:
                col_result = column_refs_for_table_in_sql(
                    ref.sql,
                    schema=impact.schema,
                    table=impact.table,
                    known_columns=before_columns,
                )
                if not col_result.target_in_query:
                    continue

                removed_set = set(impact.removed_columns)
                if col_result.verified:
                    hits = set(col_result.refs) & removed_set
                else:
                    hits = _grep_column_mentions(ref.sql, removed_set) & removed_set
                    if hits:
                        for col in sorted(hits):
                            errors.append(
                                f"{_rel(ref.doc_path)} — {ref.query_label} references "
                                f"removed/renamed column `{col}` on {fqn} "
                                f"(metadata: {impact.metadata_path}; "
                                "matched via text fallback because SQL did not parse)"
                            )
                        continue

                    removed_human = ", ".join(f"`{c}`" for c in sorted(removed_set))
                    errors.append(
                        f"{_rel(ref.doc_path)} — {ref.query_label}: could not parse "
                        f"golden-query SQL to verify column removals on {fqn} "
                        f"({col_result.verification_error or 'parse failed'}) — "
                        f"column(s) removed in {impact.metadata_path}: {removed_human}"
                    )
                    continue

                for col in sorted(hits):
                    errors.append(
                        f"{_rel(ref.doc_path)} — {ref.query_label} references "
                        f"removed/renamed column `{col}` on {fqn} "
                        f"(metadata: {impact.metadata_path})"
                    )

        if impact.added_columns and not impact.removed_columns:
            if table_key not in warned_tables:
                warned_tables.add(table_key)
                added_human = ", ".join(f"`{c}`" for c in sorted(impact.added_columns))
                warnings.append(
                    f"{fqn} is used in golden queries ({docs}) and new column(s) "
                    f"were added in {impact.metadata_path}: {added_human}. "
                    "Consider whether the entity doc should mention them."
                )

    return errors, warnings
