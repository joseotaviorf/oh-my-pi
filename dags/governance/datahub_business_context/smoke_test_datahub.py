"""Smoke-test: verify entity Markdown files have a live Data Product in DataHub.

For each non-template ``docs/llm_context/domain_entities/*.md`` the script:
  1. Derives ``data_product_id`` from the filename (``accounting_funnel`` → ``accounting-funnel``).
  2. Calls the DataHub GraphQL API and checks the Data Product exists with a name.

Prerequisites:
    export DATAHUB_GRAPHQL_URL=https://<datahub-host>/api/graphql
    export DATAHUB_TOKEN=<personal-access-token>

Beyond existence, the script can validate completeness:
  - ``--deep``        also fetch + check linked-asset count (one extra call per product)
  - ``--strict``      empty description / zero golden queries / zero assets become failures
  - ``--skip-missing`` a missing product is a warning rather than a failure (the product
                      is created/updated only on the post-merge push, so its absence on a
                      PR — whether the MD was added or edited — is expected). Intended for
                      the PR gate; the post-push step omits it and hard-fails on absence.

Usage:
    python dags/governance/datahub_business_context/smoke_test_datahub.py

    # Verbose — show full GraphQL response per entity:
    python dags/governance/datahub_business_context/smoke_test_datahub.py --verbose

    # Only MD files changed in this commit (CI push after generate-and-push):
    python dags/governance/datahub_business_context/smoke_test_datahub.py --changed-only

    # PR gate (warn-only, tolerant of new entities):
    python dags/governance/datahub_business_context/smoke_test_datahub.py --skip-missing

    # Post-push gate (hard-fail on incomplete products):
    python dags/governance/datahub_business_context/smoke_test_datahub.py --strict --deep

Exit codes:
    0 — all targeted entities verified (warnings allowed)
    1 — one or more entities missing/unreachable, or (under --strict) incomplete

CI: ``validate-datahub-entities-post-push`` runs after ``generate-and-push-datahub`` on push.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Optional

_SCRIPT_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _SCRIPT_DIR.parents[2]
# Both business and metric entities are Data Products (mirrors the generate script).
_MD_DIRS = (
    _REPO_ROOT / "docs" / "llm_context" / "domain_entities",
    _REPO_ROOT / "docs" / "llm_context" / "metric_entities",
)
_MD_PREFIXES = tuple(str(d.relative_to(_REPO_ROOT)) + "/" for d in _MD_DIRS)

GRAPHQL_URL: str = os.environ.get("DATAHUB_GRAPHQL_URL", "").strip()
TOKEN: Optional[str] = os.environ.get("DATAHUB_TOKEN", "").strip() or None

_GET_DATA_PRODUCT = """
query SmokeTestDataProduct($urn: String!) {
  dataProduct(urn: $urn) {
    urn
    properties {
      name
      description
    }
    structuredProperties {
      properties {
        structuredProperty {
          urn
        }
        values {
          ... on StringValue {
            stringValue
          }
        }
      }
    }
  }
}
"""

_LIST_ASSETS = """
query SmokeTestDataProductAssets($urn: String!) {
  dataProduct(urn: $urn) {
    entities(input: { query: "*", start: 0, count: 1000 }) {
      searchResults {
        entity {
          urn
        }
      }
    }
  }
}
"""

_LIST_ASSET_RELATIONSHIPS = """
query SmokeTestDataProductAssetRels($urn: String!) {
  dataProduct(urn: $urn) {
    relationships(input: {
      types: ["DataProductContains"]
      direction: OUTGOING
      start: 0
      count: 1000
    }) {
      total
      relationships {
        entity {
          urn
        }
      }
    }
  }
}
"""

# Minimum bars enforced only under --strict. They catch complete misses
# (empty description, zero golden queries, zero linked assets), not exact-match drift.
_MIN_DESCRIPTION_CHARS = 100
_MIN_GOLDEN_QUERIES = 1
_MIN_ASSETS = 1
# Must match load_collections_context._PENDING_TABLES_SENTINEL / _UNLINKED_TABLES_SENTINEL.
_PENDING_TABLES_SENTINEL = "Tables not yet available in DataHub"
_UNLINKED_TABLES_SENTINEL = "Tables not linked as Data Product assets"
_ZERO_ASSET_RETRY_DELAYS_SEC = (2.0, 5.0, 10.0)


def _is_metric_entity(md_path: Path) -> bool:
    """Metric Data Products live under ``metric_entities/``. They are calculations over
    tables owned by domain products and own no base assets of their own, so the
    zero-linked-assets bar does not apply to them (they surface sources via golden-query
    subjects instead)."""
    return "metric_entities" in md_path.parts


def _datahub_graphql_post(
    graphql_url: str,
    token: Optional[str],
    query: str,
    variables: dict[str, Any],
    timeout_sec: float = 60.0,
) -> tuple[Optional[dict[str, Any]], str]:
    payload = json.dumps({"query": query, "variables": variables}).encode("utf-8")
    req = urllib.request.Request(
        graphql_url,
        data=payload,
        method="POST",
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
            if int(getattr(resp, "status", None) or resp.getcode()) != 200:
                return None, "http_error"
            raw = resp.read()
            if not raw or not raw.strip():
                return None, "empty_body"
            return json.loads(raw.decode("utf-8")), "ok"
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return None, "fetch_error"


def md_path_to_data_product_id(md_path: Path) -> str:
    return md_path.stem.replace("_", "-")


def _git_merge_base() -> str:
    """SHA of the merge-base between origin/master and HEAD, or empty string on failure."""
    try:
        r = subprocess.run(
            ["git", "merge-base", "origin/master", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
            cwd=_REPO_ROOT,
        )
        return r.stdout.strip()
    except subprocess.CalledProcessError:
        return ""


def _git_changed_files() -> list[str]:
    """Files changed in this commit range (all commits on this PR branch)."""
    prev_sha = os.environ.get("CI_PREV_COMMIT_SHA", "").strip()
    curr_sha = os.environ.get("CI_COMMIT_SHA", "HEAD").strip() or "HEAD"
    if prev_sha:
        cmd = ["git", "diff", "--name-only", prev_sha, curr_sha]
    else:
        merge_base = _git_merge_base()
        cmd = (
            ["git", "diff", "--name-only", merge_base, "HEAD"]
            if merge_base
            else ["git", "diff", "--name-only", "HEAD~1", "HEAD"]
        )
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, check=True, cwd=_REPO_ROOT
        )
    except subprocess.CalledProcessError:
        result = subprocess.run(
            ["git", "show", "--name-only", "--format=", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
            cwd=_REPO_ROOT,
        )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def _git_added_mds() -> set[str]:
    """Repo-relative entity MD paths ADDED (status 'A') anywhere on this PR branch.

    Used by --skip-missing: a brand-new entity's Data Product does not exist until the
    post-merge push, so its absence on a PR is expected. A MODIFIED MD that is missing
    from DataHub is still a real failure.

    When CI provides ``CI_PREV_COMMIT_SHA`` / ``CI_COMMIT_SHA`` we use those (single-push
    range). Otherwise we diff against the merge-base with origin/master so that MDs added
    in earlier commits of a multi-commit PR are correctly flagged as ADDED.
    """
    prev_sha = os.environ.get("CI_PREV_COMMIT_SHA", "").strip()
    curr_sha = os.environ.get("CI_COMMIT_SHA", "HEAD").strip() or "HEAD"
    if prev_sha:
        cmd = ["git", "diff", "--name-status", prev_sha, curr_sha]
    else:
        merge_base = _git_merge_base()
        cmd = (
            ["git", "diff", "--name-status", merge_base, "HEAD"]
            if merge_base
            else ["git", "diff", "--name-status", "HEAD~1", "HEAD"]
        )
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, check=True, cwd=_REPO_ROOT
        )
    except subprocess.CalledProcessError:
        result = subprocess.run(
            ["git", "show", "--name-status", "--format=", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
            cwd=_REPO_ROOT,
        )
    added: set[str] = set()
    for line in result.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) >= 2 and parts[0].strip().upper().startswith("A"):
            added.add(parts[-1].strip())
    return added


def _md_rel(md_path: Path) -> str:
    """Repo-relative POSIX path for an MD (matches git diff output)."""
    return md_path.resolve().relative_to(_REPO_ROOT).as_posix()


def _load_entity_mds(*, changed_only: bool) -> list[tuple[str, Path, str]]:
    """Return [(entity_name, md_path, data_product_id)] for smoke targets."""
    changed = set(_git_changed_files()) if changed_only else None
    results: list[tuple[str, Path, str]] = []
    for md_dir in _MD_DIRS:
        if not md_dir.is_dir():
            continue
        for path in sorted(md_dir.glob("*.md")):
            if path.name.startswith("_"):
                continue
            if changed is not None and _md_rel(path) not in changed:
                continue
            pid = md_path_to_data_product_id(path)
            results.append((path.stem, path, pid))
    return sorted(results, key=lambda t: t[0])


def _fetch_data_product(urn: str) -> Optional[dict[str, Any]]:
    root, _diag = _datahub_graphql_post(
        GRAPHQL_URL, TOKEN, _GET_DATA_PRODUCT, {"urn": urn}
    )
    if root is None or root.get("errors"):
        return None
    dp = (root.get("data") or {}).get("dataProduct")
    if dp and (dp.get("properties") is not None):
        return dp
    return None


def _count_golden_queries(dp: dict[str, Any]) -> int:
    """Number of golden-query URN values set in the Data Product structured property."""
    props = ((dp.get("structuredProperties") or {}).get("properties")) or []
    for prop in props:
        sp_urn = ((prop.get("structuredProperty") or {}).get("urn")) or ""
        if "golden_query" in sp_urn:
            return len(prop.get("values") or [])
    return 0


def _skips_zero_asset_check(description: str) -> bool:
    """Publisher notes when 0 links is expected (pending ingest or lookup failure)."""
    return (
        _PENDING_TABLES_SENTINEL in description
        or _UNLINKED_TABLES_SENTINEL in description
    )


def _count_from_entities_payload(root: dict[str, Any]) -> Optional[int]:
    data_product = (root.get("data") or {}).get("dataProduct") or {}
    entities = data_product.get("entities") or {}
    results = entities.get("searchResults") or []
    return len(results) if isinstance(results, list) else None


def _count_from_relationships_payload(root: dict[str, Any]) -> Optional[int]:
    data_product = (root.get("data") or {}).get("dataProduct") or {}
    rels = data_product.get("relationships") or {}
    total = rels.get("total")
    if isinstance(total, int):
        return total
    rows = rels.get("relationships") or []
    return len(rows) if isinstance(rows, list) else None


def _fetch_asset_count_once(urn: str) -> Optional[int]:
    """Prefer the relationship graph; fall back to the search index."""
    rel_root, _diag = _datahub_graphql_post(
        GRAPHQL_URL, TOKEN, _LIST_ASSET_RELATIONSHIPS, {"urn": urn}
    )
    if rel_root is not None and not rel_root.get("errors"):
        rel_count = _count_from_relationships_payload(rel_root)
        if rel_count:
            return rel_count
    root, _diag = _datahub_graphql_post(GRAPHQL_URL, TOKEN, _LIST_ASSETS, {"urn": urn})
    if root is None or root.get("errors"):
        return None
    return _count_from_entities_payload(root)


def _fetch_asset_count(urn: str) -> Optional[int]:
    """Linked-asset total for a Data Product (extra GraphQL call — only under --deep).

    Search-index lag after ``batchSetDataProduct`` can return 0 immediately; retry with
    backoff, and prefer the ``DataProductContains`` relationship which is not indexed.
    """
    count = _fetch_asset_count_once(urn)
    if count is None or count >= _MIN_ASSETS:
        return count
    for delay in _ZERO_ASSET_RETRY_DELAYS_SEC:
        time.sleep(delay)
        count = _fetch_asset_count_once(urn)
        if count is None or count >= _MIN_ASSETS:
            return count
    return count


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Smoke-test: verify entity MDs have live Data Products in DataHub.",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Show full DataHub response per entity.",
    )
    parser.add_argument(
        "--changed-only",
        action="store_true",
        help="Validate only entity MD files changed in this commit.",
    )
    parser.add_argument(
        "--deep",
        action="store_true",
        help="Also fetch + check linked-asset count (one extra GraphQL call per product).",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help=(
            "Fail when a product has an empty description, zero golden queries, or "
            "(with --deep) zero linked assets. Without --strict these are warnings."
        ),
    )
    parser.add_argument(
        "--skip-missing",
        action="store_true",
        help=(
            "Treat a missing Data Product as a warning instead of a failure (it is "
            "created/updated only on the post-merge push, so its absence on a PR — for "
            "an added or edited MD — is expected). Intended for PR validation; the "
            "post-push step omits this flag and hard-fails on absence."
        ),
    )
    ns = parser.parse_args()

    if not GRAPHQL_URL:
        print(
            "ERROR: DATAHUB_GRAPHQL_URL is not set.\n"
            "  export DATAHUB_GRAPHQL_URL=https://<datahub-host>/api/graphql",
            file=sys.stderr,
        )
        sys.exit(1)

    entities = _load_entity_mds(changed_only=ns.changed_only)
    if not entities:
        mode = "changed MDs" if ns.changed_only else "entity MDs"
        print(f"No {mode} to validate — exiting successfully.")
        sys.exit(0)

    added_mds = _git_added_mds() if ns.skip_missing else set()

    print(f"DataHub target  : {GRAPHQL_URL}")
    print(f"Auth token      : {'set' if TOKEN else 'NOT SET'}")
    if ns.changed_only:
        print("Scope           : changed MD files in this commit only")
    print(
        f"Mode            : {'strict' if ns.strict else 'warn-only'}"
        f"{' + deep (assets)' if ns.deep else ''}"
        f"{' + skip-missing (new entities)' if ns.skip_missing else ''}"
    )
    print(f"Entities to test: {len(entities)}")
    print("─" * 60)

    passed: list[str] = []
    failed: list[tuple[str, str]] = []
    warned: list[tuple[str, str]] = []

    for entity_name, md_path, pid in entities:
        urn = f"urn:li:dataProduct:{pid}"
        rel = _md_rel(md_path)
        dp = _fetch_data_product(urn)

        if dp is None:
            if ns.skip_missing:
                # On a PR a Data Product may legitimately not exist yet: it is created
                # or updated only on the post-merge push. Whether the MD was ADDED or
                # MODIFIED, validating existence on the PR is premature — so any missing
                # product is a warning here. The post-push step (no --skip-missing) is
                # the hard gate that fails if a just-published product is still absent.
                added_note = " (new)" if rel in added_mds else " (edited)"
                warned.append(
                    (entity_name, f"not yet in DataHub — created on merge: {urn}")
                )
                print(
                    f"  ⚠ {entity_name} — not yet in DataHub{added_note}, created on merge"
                )
            else:
                failed.append((entity_name, f"entity not found: {urn}"))
                print(f"  ✗ {entity_name} ({urn})")
            continue

        name = (dp.get("properties") or {}).get("name") or "—"
        desc = (dp.get("properties") or {}).get("description") or ""
        gq_count = _count_golden_queries(dp)
        asset_count = _fetch_asset_count(urn) if ns.deep else None

        # Threshold checks — failures only under --strict, otherwise warnings.
        issues: list[str] = []
        if len(desc.strip()) < _MIN_DESCRIPTION_CHARS:
            issues.append(
                f"description {len(desc.strip())} chars < {_MIN_DESCRIPTION_CHARS}"
            )
        if gq_count < _MIN_GOLDEN_QUERIES:
            issues.append(f"{gq_count} golden queries < {_MIN_GOLDEN_QUERIES}")
        # Skip the zero-assets check when the loader noted that tables are pending
        # DataHub ingestion (the description contains the sentinel text).
        has_pending_tables = _skips_zero_asset_check(desc)
        if (
            ns.deep
            and asset_count is not None
            and asset_count < _MIN_ASSETS
            and not _is_metric_entity(md_path)
            and not has_pending_tables
        ):
            issues.append(f"{asset_count} assets < {_MIN_ASSETS}")

        detail = f"desc={len(desc.strip())}c gq={gq_count}" + (
            f" assets={asset_count}" if asset_count is not None else ""
        )

        if issues:
            reason = "; ".join(issues)
            if ns.strict:
                failed.append((entity_name, reason))
                print(f"  ✗ {entity_name}  |  {detail}  |  {reason}")
            else:
                warned.append((entity_name, reason))
                print(f"  ⚠ {entity_name}  |  {detail}  |  {reason}")
        else:
            passed.append(entity_name)
            print(f"  ✓ {entity_name}  |  name={name!r}  |  {detail}")

        if ns.verbose:
            print(f"      md={md_path.name}")
            print(f"      {json.dumps(dp, indent=4, default=str)}")

    print()
    print("═" * 60)
    print(
        f"Results: {len(passed)} passed / {len(warned)} warned / "
        f"{len(failed)} failed / {len(entities)} total"
    )

    if warned:
        print("\nWarnings:")
        for name, reason in warned:
            print(f"  ⚠ {name}: {reason}")

    if failed:
        print("\nFailed:")
        for name, reason in failed:
            print(f"  ✗ {name}: {reason}")
        sys.exit(1)

    print(
        f"\nAll {len(passed) + len(warned)} targeted Data Products verified in DataHub."
    )


if __name__ == "__main__":
    main()
