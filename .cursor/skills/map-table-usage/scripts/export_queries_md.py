#!/usr/bin/env python3
"""Generate {slug}_usage_queries.md from governance_queries.py with concrete dates."""

from __future__ import annotations

import argparse
from datetime import date, timedelta
from pathlib import Path

from governance_queries import build_governance_queries

SECTION_MAP = {
    "superset_catalog_stats": ("2 — Superset (catalog)", "Charts/datasets ACTIVE and DEPRECATED in Superset catalog"),
    "superset_active_charts": ("2 — Superset (catalog)", "ACTIVE charts with views: id, name, URL, owners"),
    "trino_usage_bundle": (
        "3 — Trino runtime",
        "Trino: runtime, superset_reason, metabase_summary, adhoc (1 scan)",
    ),
    "metabase_active_cards": ("5 — Contacts", "Metabase: executed cards — id, name, URL, creator"),
    "databricks_all_readers": ("4 — Databricks, 5 — Contacts", "Databricks: all readers (90d/30d)"),
    "superset_active_contacts": ("5 — Contacts", "Superset: owners of ACTIVE charts with views (90d/30d)"),
}

DERIVED_CSVS = [
    (
        "trino_runtime_by_tool",
        "3 — Trino runtime",
        "Executions and users by tool (90d vs 30d)",
        "trino_usage_bundle.csv",
    ),
    (
        "trino_superset_reason",
        "3 — Trino runtime",
        "Superset: dashboard vs exploratory vs filter",
        "trino_usage_bundle.csv",
    ),
    (
        "metabase_summary",
        "3 — Trino runtime",
        "Metabase: distinct cards and card executions",
        "trino_usage_bundle.csv",
    ),
    (
        "trino_adhoc_executors",
        "5 — Contacts",
        "Ad-hoc: executors by tool (full list)",
        "trino_usage_bundle.csv",
    ),
    (
        "trino_adhoc_top",
        "3 — Trino runtime",
        "Ad-hoc: top 15 users (yellowbricks, other, cdp, mcp)",
        "trino_adhoc_executors.csv",
    ),
    (
        "metabase_card_contacts",
        "5 — Contacts",
        "Metabase: card creators with executions",
        "metabase_active_cards.csv",
    ),
    (
        "databricks_reads",
        "4 — Databricks",
        "Direct reads: TOTAL row + top 25 readers",
        "databricks_all_readers.csv",
    ),
]

PIPELINE_INDEX_DESC = (
    "Table usage across the repo (`dags/**/*.sql`) — **no SQL query**"
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--schema", required=True)
    parser.add_argument("--table", required=True)
    parser.add_argument("--catalog", default="quintoandar_prod")
    parser.add_argument("--cluster", default="")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--end-date", type=date.fromisoformat, default=None)
    parser.add_argument(
        "--analysis-md",
        default="",
        help="Filename of the analysis report (default: {slug}_usage_deprecation_analysis.md)",
    )
    args = parser.parse_args()

    slug = f"{args.schema}__{args.table}"
    end = args.end_date or date.today()
    start_90d = end - timedelta(days=90)
    start_30d = end - timedelta(days=30)
    analysis_name = args.analysis_md or f"{slug}_usage_deprecation_analysis.md"
    raw_dir = f"{slug}_raw_data"

    specs = build_governance_queries(
        catalog=args.catalog,
        schema=args.schema,
        table=args.table,
        start_90d=start_90d.isoformat(),
        end_90d=end.isoformat(),
        start_30d=start_30d.isoformat(),
    )

    lines: list[str] = [
        f"# SQL queries — usage mapping `{args.schema}.{args.table}`",
        "",
        f"Analysis report: [`{analysis_name}`]({analysis_name})",
        "",
        "This file lists **governance SQL queries** that fed the report. "
        "Sources without SQL (e.g. repo scan) appear in the index only. "
        "Derived CSVs (Python post-processing, no extra SQL) are in the index below. "
        f"Tabular results in [`{raw_dir}/`]({raw_dir}/).",
        "",
        "## Parameters",
        "",
        "| Parameter | Value |",
        "| --- | --- |",
        f"| Table | `{args.schema}.{args.table}` |",
        f"| UC catalog | `{args.catalog}` |",
        f"| 90-day window | `{start_90d}` → `{end}` |",
        f"| 30-day window | `{start_30d}` → `{end}` |",
    ]
    if args.cluster:
        lines.append(f"| Databricks cluster | `{args.cluster}` (profile PROD) |")
    lines.extend(
        [
            "",
            "## Index — query → result",
            "",
            "| Query | What it measures | Report section | CSV |",
            "| --- | --- | --- | --- |",
        ]
    )
    for spec in specs:
        section, desc = SECTION_MAP.get(spec.name, ("?", spec.description))
        lines.append(f"| `{spec.name}` | {desc} | {section} | `{spec.name}.csv` |")
    for name, desc, section, source in DERIVED_CSVS:
        lines.append(
            f"| `{name}` (derived) | {desc} | {section} | `{name}.csv` ← `{source}` |"
        )
    lines.append(
        f"| Pipeline (repo) | {PIPELINE_INDEX_DESC} | 1 — Pipeline | `pipeline_consumers.csv` |"
    )
    lines.extend(
        [
            "",
            "Post-processing: `postprocess_csvs.py` (called automatically by `run_governance_batch.py`).",
        ]
    )

    for spec in specs:
        section, desc = SECTION_MAP.get(spec.name, ("?", spec.description))
        lines.extend(
            [
                "",
                "---",
                "",
                f"## `{spec.name}` — {desc}",
                "",
                f"**Report section:** {section}  ",
                f"**Output file:** `{raw_dir}/{spec.name}.csv`",
                "",
                "```sql",
                spec.sql.strip(),
                "```",
            ]
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
