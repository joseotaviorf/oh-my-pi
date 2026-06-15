"""Smoke-test: verify entity Markdown files have a live Data Product in DataHub.

For each non-template ``docs/llm_context/business_entities/*.md`` the script:
  1. Derives ``data_product_id`` from the filename (``accounting_funnel`` → ``accounting-funnel``).
  2. Calls the DataHub GraphQL API and checks the Data Product exists with a name.

Prerequisites:
    export DATAHUB_GRAPHQL_URL=https://<datahub-host>/api/graphql
    export DATAHUB_TOKEN=<personal-access-token>

Usage:
    python dags/governance/datahub_business_context/smoke_test_datahub.py

    # Verbose — show full GraphQL response per entity:
    python dags/governance/datahub_business_context/smoke_test_datahub.py --verbose

    # Only MD files changed in this commit (CI push after generate-and-push):
    python dags/governance/datahub_business_context/smoke_test_datahub.py --changed-only

Exit codes:
    0 — all targeted entities verified
    1 — one or more entities missing or unreachable

CI: ``validate-datahub-entities-push`` runs after ``generate-and-push-datahub`` on push.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Optional

_SCRIPT_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _SCRIPT_DIR.parents[2]
_MD_DIR = _REPO_ROOT / "docs" / "llm_context" / "business_entities"
_MD_PREFIX = "docs/llm_context/business_entities/"

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
  }
}
"""


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


def _git_changed_files() -> list[str]:
    prev_sha = os.environ.get("CI_PREV_COMMIT_SHA", "").strip()
    curr_sha = os.environ.get("CI_COMMIT_SHA", "HEAD").strip() or "HEAD"
    if prev_sha:
        cmd = ["git", "diff", "--name-only", prev_sha, curr_sha]
    else:
        cmd = ["git", "diff", "--name-only", "HEAD~1", "HEAD"]
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


def _load_entity_mds(*, changed_only: bool) -> list[tuple[str, Path, str]]:
    """Return [(entity_name, md_path, data_product_id)] for smoke targets."""
    changed = set(_git_changed_files()) if changed_only else None
    results: list[tuple[str, Path, str]] = []
    for path in sorted(_MD_DIR.glob("*.md")):
        if path.name.startswith("_"):
            continue
        rel = f"{_MD_PREFIX}{path.name}"
        if changed is not None and rel not in changed:
            continue
        pid = md_path_to_data_product_id(path)
        results.append((path.stem, path, pid))
    return results


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

    print(f"DataHub target  : {GRAPHQL_URL}")
    print(f"Auth token      : {'set' if TOKEN else 'NOT SET'}")
    if ns.changed_only:
        print("Scope           : changed MD files in this commit only")
    print(f"Entities to test: {len(entities)}")
    print("─" * 60)

    passed: list[str] = []
    failed: list[tuple[str, str]] = []

    for entity_name, md_path, pid in entities:
        urn = f"urn:li:dataProduct:{pid}"
        dp = _fetch_data_product(urn)

        if dp is None:
            failed.append((entity_name, f"entity not found: {urn}"))
            print(f"  ✗ {entity_name} ({urn})")
        else:
            name = (dp.get("properties") or {}).get("name") or "—"
            print(f"  ✓ {entity_name}  |  name={name!r}  |  urn={urn}")
            if ns.verbose:
                print(f"      md={md_path.name}")
                print(f"      {json.dumps(dp, indent=4, default=str)}")
            passed.append(entity_name)

    print()
    print("═" * 60)
    print(
        f"Results: {len(passed)} passed / {len(failed)} failed / {len(entities)} total"
    )

    if failed:
        print("\nFailed:")
        for name, reason in failed:
            print(f"  ✗ {name}: {reason}")
        sys.exit(1)

    print(f"\nAll {len(passed)} Data Products verified in DataHub.")


if __name__ == "__main__":
    main()
