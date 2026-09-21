#!/usr/bin/env python3
"""CI gate: validate golden-query SQL in entity docs against repo metadata YAML.

For each ``docs/llm_context/{business,metric}_entities/*.md`` in scope, parses golden
queries and checks Trino SQL syntax (sqlglot, dialect ``trino``) plus that referenced
``schema.table`` pairs and column names exist in ``dags/**/metadata/**/*.yml`` (with an
optional read-only DataHub catalog fallback for tables without repo metadata YAML).
Does **not** execute SQL on Trino.

Usage:
    python validate_entity_golden_queries_metadata.py --changed-only -b "$CI_COMMIT_BRANCH"
    python validate_entity_golden_queries_metadata.py --all
    python validate_entity_golden_queries_metadata.py --paths docs/llm_context/metric_entities/nps_fr.md

Exit codes: 0 = pass (warnings allowed); 1 = blocking error or bad invocation.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

from bietlejuice.ci.ci_diff_ref import resolve_diff_from_ref

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from datahub_table_fallback import build_datahub_fallback_client  # noqa: E402
from golden_query_metadata_validator import (  # noqa: E402
    MetadataSchemaClient,
    build_metadata_column_index,
)
from golden_query_schema_validator import (  # noqa: E402
    GoldenQuerySchemaClient,
    validate_golden_queries,
)
from validate_datahub_context_entities import (  # noqa: E402
    _DOMAIN_DIR,
    _METRIC_DIR,
    _all_entity_files,
    _data_product_type,
    _filter_entity_paths,
    _git_changed_entity_files,
    _maybe_comment_on_pr,
    _maybe_comment_success,
    _rel,
    _template_hint,
)


def _validate_file(
    path: Path, client: GoldenQuerySchemaClient
) -> tuple[list[str], list[str]]:
    from sync.document_parser import parse_entity_markdown
    from sync.markdown_sanitizer import sanitize_uploaded_markdown

    try:
        content = path.read_text(encoding="utf-8")
    except OSError as exc:
        return [f"could not read file: {exc}"], []

    parsed = parse_entity_markdown(
        content,
        unescape=False,
        sanitize_fn=sanitize_uploaded_markdown,
    )
    return validate_golden_queries(parsed.golden_queries, client=client)


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate golden-query SQL in DataHub context entity .md files "
            "against repo metadata YAML under dags/."
        )
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--changed-only",
        action="store_true",
        help="Validate only entity docs changed vs the diff base (CI).",
    )
    group.add_argument(
        "--all",
        action="store_true",
        help="Validate every committed entity doc (local audit).",
    )
    group.add_argument(
        "--paths",
        nargs="+",
        type=Path,
        help="Explicit .md paths to validate (local testing).",
    )
    parser.add_argument(
        "-b",
        "--branch",
        default=os.environ.get("CI_COMMIT_BRANCH", ""),
        help="Current branch (CI_COMMIT_BRANCH); used with --changed-only.",
    )
    parser.add_argument(
        "--no-datahub-fallback",
        action="store_true",
        help=(
            "Skip the DataHub catalog probe for tables missing repo metadata YAML "
            "(default: probe DataHub when DATAHUB_GRAPHQL_URL/DATAHUB_TOKEN are set)."
        ),
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)

    if args.paths:
        files = _filter_entity_paths(args.paths)
        if not files:
            print(
                "✗ none of the given --paths are entity .md files under "
                f"{_DOMAIN_DIR}/ or {_METRIC_DIR}/",
                file=sys.stderr,
            )
            return 1
        print(f"Scope           : {len(files)} explicitly-listed entity doc(s)")
    elif args.all:
        files = _all_entity_files()
        print(f"Scope           : every committed entity doc ({len(files)})")
    else:
        from_ref = resolve_diff_from_ref(args.branch)
        print(
            f"Scope           : entity docs changed vs {from_ref} "
            f"({from_ref}...HEAD — whole branch delta, not just the last commit)"
        )
        try:
            files = _git_changed_entity_files(args.branch)
        except subprocess.CalledProcessError as exc:
            print(f"✗ git diff failed: {exc}", file=sys.stderr)
            return 1
        if not files:
            print("No changed entity docs detected — nothing to validate.")
            return 0

    index = build_metadata_column_index()
    client: GoldenQuerySchemaClient = MetadataSchemaClient(index=index)
    print(
        f"Validating golden queries in {len(files)} entity doc(s) against "
        f"{len(index)} metadata table(s)…"
    )

    if args.no_datahub_fallback:
        print("DataHub fallback: disabled (--no-datahub-fallback)")
    else:
        graphql_url = os.environ.get("DATAHUB_GRAPHQL_URL", "").strip()
        token = os.environ.get("DATAHUB_TOKEN", "").strip()
        client = build_datahub_fallback_client(
            client, graphql_url=graphql_url, token=token
        )
        if graphql_url and token:
            print(
                "DataHub fallback: enabled — tables absent from repo metadata are "
                "probed against DataHub before being reported as errors"
            )
        else:
            print("DataHub fallback: no-op (DATAHUB_GRAPHQL_URL/DATAHUB_TOKEN not set)")

    n_failed = 0
    n_warnings = 0
    failures: list[tuple[str, str, list[str]]] = []
    for path in files:
        rel = _rel(path)
        dp_type = _data_product_type(path)
        errors, warnings = _validate_file(path, client)
        n_warnings += len(warnings)
        for w in warnings:
            print(f"  ⚠ {rel}: {w}")
        if errors:
            n_failed += 1
            failures.append((str(rel), dp_type, errors))
            print(f"  ✗ {rel} ({dp_type}, {len(errors)} error(s)):", file=sys.stderr)
            for e in errors:
                print(f"      • {e}", file=sys.stderr)
            print(f"      → see the template: {_template_hint(path)}", file=sys.stderr)
        else:
            print(f"  ✓ {rel} ({dp_type})")

    if n_warnings:
        print(f"\n{n_warnings} warning(s) — non-blocking.")

    if n_failed:
        _maybe_comment_on_pr(failures)
        print(
            f"\n✗ {n_failed} entity doc(s) failed golden-query metadata validation.",
            file=sys.stderr,
        )
        return 1

    print("\n✓ All golden queries pass repo metadata validation.")
    _maybe_comment_success()
    return 0


if __name__ == "__main__":
    sys.exit(main())
