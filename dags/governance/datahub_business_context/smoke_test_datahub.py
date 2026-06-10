"""Smoke-test: verify every *.datahub.yaml entity is reachable in DataHub.

For each non-template YAML in ``datahub_entities/`` the script:
  1. Derives the expected Data Product URN from data_product_id.
  2. Calls the DataHub GraphQL API and checks the entity exists with a name.
  3. Reports pass / fail per entity and exits non-zero if any entity is missing.

Prerequisites:
    export DATAHUB_GRAPHQL_URL=https://<datahub-host>/api/graphql
    export DATAHUB_TOKEN=<personal-access-token>

Usage:
    python dags/governance/datahub_business_context/smoke_test_datahub.py

    # Verbose — show full GraphQL response per entity:
    python dags/governance/datahub_business_context/smoke_test_datahub.py --verbose

Exit codes:
    0 — all entities verified
    1 — one or more entities missing or unreachable

CI: invoked by ``.woodpecker/datahub.yml`` step ``validate-datahub-entities`` (secrets: graphql URL + token).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Optional

import yaml


def _datahub_graphql_post(
    graphql_url: str,
    token: Optional[str],
    query: str,
    variables: dict[str, Any],
    timeout_sec: float = 60.0,
) -> tuple[Optional[dict[str, Any]], str]:
    """POST GraphQL; stdlib-only so Woodpecker CI needs no bietlejuice deps."""
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


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

GRAPHQL_URL: str = os.environ.get("DATAHUB_GRAPHQL_URL", "").strip()
TOKEN: Optional[str] = os.environ.get("DATAHUB_TOKEN", "").strip() or None

_SCRIPT_DIR = Path(__file__).resolve().parent
_ENTITY_CONFIG_DIR = _SCRIPT_DIR / "datahub_entities"

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


def _fetch_data_product(urn: str) -> Optional[dict[str, Any]]:
    root, _diag = _datahub_graphql_post(
        GRAPHQL_URL, TOKEN, _GET_DATA_PRODUCT, {"urn": urn}
    )
    if root is None:
        return None
    if root.get("errors"):
        return None
    data = root.get("data") or {}
    dp = data.get("dataProduct")
    # DataHub returns a non-null shell for unknown URNs; only real entities have properties.
    if dp and (dp.get("properties") is not None):
        return dp
    return None


def _load_all_configs() -> list[tuple[str, dict[str, Any]]]:
    """Return [(entity_name, spec_dict)] for all non-template YAML files."""
    results = []
    for path in sorted(_ENTITY_CONFIG_DIR.glob("*.datahub.yaml")):
        if path.name.startswith("_"):
            continue
        with path.open(encoding="utf8") as fh:
            spec = yaml.safe_load(fh)
        if not isinstance(spec, dict):
            continue
        entity_name = path.stem.removesuffix(".datahub")
        results.append((entity_name, spec))
    return results


def _data_product_id_from_spec(spec: dict[str, Any]) -> Optional[str]:
    """Extract data_product_id: present in data_product_curated_entity; derived from
    bundle_id for full_curated_datahub_bundle."""
    pid = spec.get("data_product_id")
    if pid:
        return str(pid).strip()
    # full_curated_datahub_bundle: data_product_id lives inside the bundle module;
    # fall back to bundle_id slug used as the product identifier.
    bid = spec.get("bundle_id")
    if bid:
        return str(bid).replace("_", "-").strip()
    return None


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Smoke-test: verify all DataHub Data Products are live.",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Show full DataHub response per entity.",
    )
    ns = parser.parse_args()

    if not GRAPHQL_URL:
        print(
            "ERROR: DATAHUB_GRAPHQL_URL is not set.\n"
            "  export DATAHUB_GRAPHQL_URL=https://<datahub-host>/api/graphql",
            file=sys.stderr,
        )
        sys.exit(1)

    configs = _load_all_configs()
    if not configs:
        print(
            f"No *.datahub.yaml files found in {_ENTITY_CONFIG_DIR}.",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"DataHub target  : {GRAPHQL_URL}")
    print(f"Auth token      : {'set' if TOKEN else 'NOT SET'}")
    print(f"Entities to test: {len(configs)}")
    print("─" * 60)

    passed: list[str] = []
    failed: list[tuple[str, str]] = []

    for entity_name, spec in configs:
        pid = _data_product_id_from_spec(spec)
        if not pid:
            failed.append(
                (entity_name, "could not determine data_product_id from YAML")
            )
            print(f"  ✗ {entity_name}: no data_product_id in YAML")
            continue

        urn = f"urn:li:dataProduct:{pid}"
        dp = _fetch_data_product(urn)

        if dp is None:
            failed.append((entity_name, f"entity not found: {urn}"))
            print(f"  ✗ {entity_name} ({urn})")
        else:
            name = (dp.get("properties") or {}).get("name") or "—"
            print(f"  ✓ {entity_name}  |  name={name!r}  |  urn={urn}")
            if ns.verbose:
                print(f"      {json.dumps(dp, indent=4, default=str)}")
            passed.append(entity_name)

    print()
    print("═" * 60)
    print(
        f"Results: {len(passed)} passed / {len(failed)} failed / {len(configs)} total"
    )

    if failed:
        print("\nFailed:")
        for name, reason in failed:
            print(f"  ✗ {name}: {reason}")
        sys.exit(1)

    print(f"\nAll {len(passed)} Data Products verified in DataHub.")


if __name__ == "__main__":
    main()
