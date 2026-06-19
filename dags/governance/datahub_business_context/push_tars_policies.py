"""Push TARS entity metadata policies to DataHub via GraphQL.

Reads ``policies/tars_entity_metadata_policies.yml``, expands per-domain
templates, deduplicates by name (idempotent — finds and updates existing
policies instead of creating duplicates), and applies each one.

Usage:
    export DATAHUB_GRAPHQL_URL=https://<datahub-host>/api/graphql
    export DATAHUB_TOKEN=<personal-access-token-with-manage-policies-privilege>
    python dags/governance/datahub_business_context/push_tars_policies.py

    # Dry-run — print actions without calling DataHub:
    python dags/governance/datahub_business_context/push_tars_policies.py --dry-run

Notes on the YAML → GraphQL mapping:
    - YAML criterion field ``ENTITY`` → GraphQL ``TYPE`` (valid fields:
      TYPE, TAG, DOMAIN, URN, OWNER, RESOURCE_TYPE, etc.)
    - YAML condition ``EQUAL`` → GraphQL ``EQUALS``
    - Privilege ``EDIT_DOCUMENT_CONTENT`` → mapped to ``EDIT_ENTITY``
    - "Contributors cannot publish" DENY policy: DataHub's GraphQL API has no
      deny-effect concept — this policy is skipped; apply the DENY effect
      manually in the UI (Settings → Access → Policies) if needed.

Exit codes: 0 = all policies applied; 1 = at least one failure.
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

# ---------------------------------------------------------------------------
# GraphQL client
# ---------------------------------------------------------------------------

GRAPHQL_URL: str = os.environ.get("DATAHUB_GRAPHQL_URL", "").strip()
TOKEN: Optional[str] = os.environ.get("DATAHUB_TOKEN", "").strip() or None

_SCRIPT_DIR = Path(__file__).resolve().parent
_POLICIES_FILE = _SCRIPT_DIR / "policies" / "tars_entity_metadata_policies.yml"

_errors: list[str] = []


def _graphql_post(
    query: str,
    variables: dict[str, Any],
    timeout_sec: float = 60.0,
) -> tuple[Optional[dict[str, Any]], str]:
    payload = json.dumps({"query": query, "variables": variables}).encode("utf-8")
    req = urllib.request.Request(
        GRAPHQL_URL,
        data=payload,
        method="POST",
        headers={"Accept": "application/json", "Content-Type": "application/json"},
    )
    if TOKEN:
        req.add_header("Authorization", f"Bearer {TOKEN}")
    try:
        with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
            raw = resp.read()
            return json.loads(raw.decode("utf-8")), "ok"
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:300]
        return None, f"http_{exc.code}: {detail}"
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as exc:
        return None, f"fetch_error: {exc}"


def _post(query: str, variables: dict[str, Any]) -> Optional[dict[str, Any]]:
    root, diag = _graphql_post(query, variables)
    if root is None:
        print(f"    [DEBUG] {diag}", file=sys.stderr)
        return None
    if root.get("errors"):
        print(
            f"    [DEBUG] GraphQL errors: {json.dumps(root['errors'])[:500]}",
            file=sys.stderr,
        )
    return root.get("data")


def _ok(label: str) -> None:
    print(f"  \u2713 {label}")


def _fail(label: str, detail: str) -> None:
    msg = f"  \u2717 {label}: {detail}"
    print(msg, file=sys.stderr)
    _errors.append(msg)


# ---------------------------------------------------------------------------
# Policy CRUD
# ---------------------------------------------------------------------------

_LIST_POLICIES = """
query ListPolicies($input: ListPoliciesInput!) {
  listPolicies(input: $input) {
    total
    policies { urn name state }
  }
}
"""

_CREATE_POLICY = """
mutation CreatePolicy($input: PolicyUpdateInput!) {
  createPolicy(input: $input)
}
"""

_UPDATE_POLICY = """
mutation UpdatePolicy($urn: String!, $input: PolicyUpdateInput!) {
  updatePolicy(urn: $urn, input: $input)
}
"""


def _find_policy_urn(name: str) -> Optional[str]:
    """Return the URN of an existing policy with this exact name, or None."""
    data = _post(_LIST_POLICIES, {"input": {"start": 0, "count": 200, "query": name}})
    if data is None:
        return None
    for p in (data.get("listPolicies") or {}).get("policies") or []:
        if p.get("name") == name:
            return p["urn"]
    return None


def _apply_policy(inp: dict[str, Any], *, dry_run: bool) -> bool:
    name = inp["name"]
    if dry_run:
        _ok(f"[dry-run] would upsert policy: {name!r}")
        return True

    existing_urn = _find_policy_urn(name)

    if existing_urn:
        data = _post(_UPDATE_POLICY, {"urn": existing_urn, "input": inp})
        if data is None:
            _fail(name, "updatePolicy failed")
            return False
        _ok(f"updated {existing_urn}  ({name!r})")
    else:
        data = _post(_CREATE_POLICY, {"input": inp})
        if data is None:
            _fail(name, "createPolicy failed")
            return False
        created_urn = (data or {}).get("createPolicy")
        _ok(f"created {created_urn}  ({name!r})")

    return True


# ---------------------------------------------------------------------------
# YAML → GraphQL mapping
# ---------------------------------------------------------------------------

# Privilege aliases: YAML names that don't exist verbatim in DataHub → real name
_PRIVILEGE_MAP: dict[str, str] = {
    "EDIT_DOCUMENT_CONTENT": "EDIT_ENTITY",
    "MANAGE_DOCUMENTS": "MANAGE_DOCUMENTS",  # platform-level only; included anyway
}

# Criterion field aliases
_FIELD_MAP: dict[str, str] = {
    "ENTITY": "TYPE",  # YAML says ENTITY, GraphQL wants TYPE
    "ENTITY_TYPE": "TYPE",
}

# Condition aliases
_CONDITION_MAP: dict[str, str] = {
    "EQUAL": "EQUALS",
}

# Policies to skip (no GraphQL equivalent)
_SKIP_NAMES_CONTAINING = ["cannot publish"]  # DENY-effect policies


def _map_privilege(p: str) -> str:
    return _PRIVILEGE_MAP.get(p, p)


def _map_criterion(c: dict[str, Any]) -> dict[str, Any]:
    field = _FIELD_MAP.get(str(c.get("field", "")), str(c.get("field", "")))
    values = c.get("values", [])
    if isinstance(values, list):
        values = [str(v).lower() if field == "TYPE" else str(v) for v in values]
    condition = _CONDITION_MAP.get(
        str(c.get("condition", "EQUALS")), str(c.get("condition", "EQUALS"))
    )
    return {"field": field, "values": values, "condition": condition}


def _build_input(
    policy_spec: dict[str, Any], substitutions: dict[str, str]
) -> dict[str, Any]:
    """Build a PolicyUpdateInput dict from a policy spec, applying template substitutions."""

    def _sub(val: Any) -> Any:
        if isinstance(val, str):
            for k, v in substitutions.items():
                val = val.replace("{{ " + k + " }}", v)
            return val
        if isinstance(val, list):
            return [_sub(i) for i in val]
        if isinstance(val, dict):
            return {k: _sub(v) for k, v in val.items()}
        return val

    spec = _sub(policy_spec)

    privileges = [_map_privilege(p) for p in (spec.get("privileges") or [])]

    resources_spec = spec.get("resources") or {}
    criteria = [
        _map_criterion(c)
        for c in ((resources_spec.get("filter") or {}).get("criteria") or [])
    ]

    actors_spec = spec.get("actors") or {}
    actors: dict[str, Any] = {
        "resourceOwners": False,
        "allUsers": bool(actors_spec.get("allUsers", False)),
        "allGroups": bool(actors_spec.get("allGroups", False)),
    }
    if "groups" in actors_spec:
        actors["groups"] = actors_spec["groups"]
    if "users" in actors_spec:
        actors["users"] = actors_spec["users"]

    return {
        "type": str(spec.get("type", "METADATA")),
        "name": str(spec.get("name", "")),
        "state": str(spec.get("state", "ACTIVE")),
        "description": str(spec.get("description", "")),
        "privileges": privileges,
        "resources": {"filter": {"criteria": criteria}},
        "actors": actors,
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Push TARS entity metadata policies to DataHub (idempotent).",
    )
    parser.add_argument("--dry-run", action="store_true")
    ns = parser.parse_args()

    if not ns.dry_run and not GRAPHQL_URL:
        print("ERROR: DATAHUB_GRAPHQL_URL is not set.", file=sys.stderr)
        return 1

    with _POLICIES_FILE.open(encoding="utf-8") as fh:
        spec = yaml.safe_load(fh)

    policies_spec: list[dict[str, Any]] = spec.get("policies") or []
    domain_stewards: dict[str, dict[str, str]] = spec.get("domain_stewards") or {}
    governance_admin_group: str = str(spec.get("governance_admin_group", ""))

    print(f"DataHub target  : {GRAPHQL_URL or '(dry-run)'}")
    print(
        f"Auth token      : {'set' if TOKEN else ('NOT SET' if not ns.dry_run else '(dry-run)')}"
    )
    print(f"Policy templates: {len(policies_spec)}")
    print(f"Domains         : {list(domain_stewards.keys())}")
    print("────────────────────────────────────────────────────────────")

    passed: list[str] = []
    skipped: list[str] = []

    for policy_spec in policies_spec:
        name: str = str(policy_spec.get("name", ""))

        # Skip DENY-effect policies — no GraphQL equivalent
        if any(s in name.lower() for s in _SKIP_NAMES_CONTAINING):
            msg = f"  ↷  SKIPPED (no GraphQL deny-effect): {name!r}"
            print(msg)
            skipped.append(name)
            continue

        # Determine if this is a per-domain or global policy
        is_domain_scoped = "{{ domain_urn }}" in json.dumps(policy_spec)

        if is_domain_scoped:
            for domain, domain_cfg in domain_stewards.items():
                domain_name = f"{name} [{domain}]"
                print(f"\n▶  {domain_name}")
                substitutions = {
                    "domain_urn": domain_cfg.get("domain_urn", ""),
                    "steward_group": domain_cfg.get("steward_group", ""),
                    "contributor_group": domain_cfg.get("contributor_group", ""),
                }
                inp = _build_input(policy_spec, substitutions)
                inp["name"] = domain_name  # make name unique per domain
                ok = _apply_policy(inp, dry_run=ns.dry_run)
                if ok:
                    passed.append(domain_name)
                else:
                    _errors.append(domain_name)
        else:
            print(f"\n▶  {name}")
            substitutions = {
                "governance_admin_group": governance_admin_group,
            }
            inp = _build_input(policy_spec, substitutions)
            ok = _apply_policy(inp, dry_run=ns.dry_run)
            if ok:
                passed.append(name)
            else:
                _errors.append(name)

    print("\n" + "═" * 60)
    print(
        f"Results: {len(passed)} applied / {len(_errors)} failed / "
        f"{len(skipped)} skipped (deny-effect) / {len(policies_spec)} templates"
    )

    if skipped:
        print("\nSkipped (apply manually as DENY effect in DataHub UI):")
        for name in skipped:
            print(f"  ↷  {name}")

    if _errors:
        print("\nFailed:")
        for name in _errors:
            print(f"  \u2717  {name}")
        return 1

    print(f"\nAll {len(passed)} policies applied successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
