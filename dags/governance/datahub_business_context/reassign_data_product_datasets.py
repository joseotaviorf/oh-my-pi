#!/usr/bin/env python3
"""One-time, targeted reassignment of datasets between DataHub Data Products.

The curated loader (``load_collections_context.py``) is fail-closed: it refuses to take a
dataset away from its current Data Product (``_filter_assignable_urns``), so ownership
transfers cannot happen through a normal resync. This tool performs an explicit, audited
move for a small allow-list of ``(dataset, expected current owner, new owner)`` triples.

``batchSetDataProduct`` is exclusive — assigning a dataset to the new product removes it
from the old one automatically. Each move is guarded: it only runs when the dataset's
*current* owner matches the expected old owner, so a stale/incorrect entry is skipped
rather than silently stealing a dataset.

Run order matters: execute this BEFORE merging the Markdown changes that drop these tables
from the old owners' docs (after the move, future resyncs are stable with no loader change).

Usage:
    # dry run (default) — prints what WOULD move, mutates nothing
    uv run python dags/governance/datahub_business_context/reassign_data_product_datasets.py

    # apply for real (requires DATAHUB_GRAPHQL_URL + DATAHUB_TOKEN with editor role)
    uv run python .../reassign_data_product_datasets.py --apply
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from load_collections_context import (  # noqa: E402
    _OWNER_UNKNOWN,
    _SET_DATA_PRODUCT_ASSETS,
    _data_product_urn,
    _entity_exists,
    _get_asset_current_product_urn,
    _post,
)


def _trino_urn(schema: str, table: str) -> str:
    return f"urn:li:dataset:(urn:li:dataPlatform:trino,hive.{schema}.{table},PROD)"


# (schema, table, expected current owner product id, new owner product id)
# Trino URNs are used because that is what the loader resolves to and what currently
# holds the ownership link (see CI log ownership-conflict entries).
REASSIGNMENTS: list[tuple[str, str, str, str]] = [
    ("datalake_chatbot", "evals", "chatbot-sessions", "evals"),
    ("dw_visit", "fact_visits", "visit-context", "visits"),
    ("dw_visit", "fact_visit_schedules", "visit-context", "visits"),
    ("dw_visit", "dim_visit", "visit-context", "visits"),
    ("dw_visit", "dim_visit_schedule", "visit-context", "visits"),
    ("dw_visit", "dim_post_visit_demand", "visit-context", "visits"),
]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Perform the moves. Without this flag the script is a dry run.",
    )
    ns = parser.parse_args(argv if argv is not None else sys.argv[1:])

    mode = "APPLY" if ns.apply else "DRY RUN"
    print(f"Reassign Data Product datasets — {mode}")
    print("─" * 60)

    moved = 0
    skipped = 0
    failed = 0

    for schema, table, expected_old, new_owner in REASSIGNMENTS:
        urn = _trino_urn(schema, table)
        label = f"{schema}.{table}"
        expected_old_urn = _data_product_urn(expected_old)
        new_owner_urn = _data_product_urn(new_owner)

        if not _entity_exists(urn):
            print(f"  ! SKIP {label}: dataset not found in DataHub ({urn})")
            skipped += 1
            continue

        current = _get_asset_current_product_urn(urn)
        if current is _OWNER_UNKNOWN:
            print(f"  ! SKIP {label}: ownership lookup failed — retry when reachable")
            skipped += 1
            continue
        if current == new_owner_urn:
            print(f"  = OK   {label}: already owned by {new_owner} — nothing to do")
            skipped += 1
            continue
        if current != expected_old_urn:
            print(
                f"  ! SKIP {label}: current owner {current!r} != expected "
                f"{expected_old_urn!r}. Refusing to move (guard)."
            )
            skipped += 1
            continue

        print(f"  → MOVE {label}: {expected_old} → {new_owner}")
        if not ns.apply:
            moved += 1
            continue

        res = _post(
            _SET_DATA_PRODUCT_ASSETS,
            {"input": {"dataProductUrn": new_owner_urn, "resourceUrns": [urn]}},
        )
        if res is None:
            print(f"    ✗ batchSetDataProduct failed for {label}")
            failed += 1
        else:
            print(f"    ✓ moved {label} to {new_owner}")
            moved += 1

    print("─" * 60)
    print(
        f"{'Would move' if not ns.apply else 'Moved'}: {moved} | skipped: {skipped} | failed: {failed}"
    )
    if not ns.apply and moved:
        print("Re-run with --apply to perform the moves.")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
