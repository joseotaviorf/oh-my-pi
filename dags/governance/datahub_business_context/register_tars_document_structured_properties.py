"""Register structured properties on DataHub Context Documents for TARS entity sync.

These properties appear in the document sidebar and are consumed by
``sync_tars_entities.py`` when generating ``*.datahub.yaml`` files.

Usage:
    export DATAHUB_GRAPHQL_URL=https://<datahub-host>/api/graphql
    export DATAHUB_TOKEN=<personal-access-token-with-editor-role>
    python dags/governance/datahub_business_context/register_tars_document_structured_properties.py

Exit codes: 0 = all properties registered; 1 = at least one failure.
"""

from __future__ import annotations

import json
import os
import sys
from typing import Any, Optional

# Bootstrap GraphQL client (same pattern as load_collections_context.py)
_repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
_runtime_src = os.path.join(_repo_root, "packages", "bietlejuice-runtime", "src")
for _p in (_runtime_src, _repo_root):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from bietlejuice.governance.fairness_assessment.datahub_graphql.client import (  # noqa: E402
    datahub_graphql_post,
)

GRAPHQL_URL = os.environ.get("DATAHUB_GRAPHQL_URL", "").strip()
TOKEN: Optional[str] = os.environ.get("DATAHUB_TOKEN", "").strip() or None

DOCUMENT_ENTITY_TYPE = "urn:li:entityType:datahub.document"
STRING_VALUE_TYPE = "urn:li:dataType:datahub.string"

# Qualified names consumed by sync/datahub_document_client.py
TARS_DOCUMENT_PROPERTIES: list[dict[str, Any]] = [
    {
        "qualifiedName": "br.com.quintoandar.datahub.tars_entity.domain_urn",
        "displayName": "Domain URN",
        "description": (
            "DataHub domain URN for this entity, e.g. urn:li:domain:fintech. "
            "Required for Data Product creation."
        ),
        "cardinality": "SINGLE",
    },
    {
        "qualifiedName": "br.com.quintoandar.datahub.tars_entity.data_product_id",
        "displayName": "Data Product ID",
        "description": (
            "Kebab-case slug for the derived Data Product, e.g. collections. "
            "Becomes urn:li:dataProduct:{id}."
        ),
        "cardinality": "SINGLE",
    },
    {
        "qualifiedName": "br.com.quintoandar.datahub.tars_entity.primary_datasets",
        "displayName": "Primary datasets",
        "description": (
            "Comma-separated schema.table pairs belonging to this entity, "
            "e.g. dw_losses.fact_accounts_receivable,dw_payments_platform.fact_payment."
        ),
        "cardinality": "SINGLE",
    },
    {
        "qualifiedName": "br.com.quintoandar.datahub.tars_entity.golden_query_stable_urn",
        "displayName": "Golden query stable URN",
        "description": (
            "Stable Query entity URN (urn:li:query:{uuid4}). "
            "Generate once on first publication; never change."
        ),
        "cardinality": "SINGLE",
    },
    {
        "qualifiedName": "br.com.quintoandar.datahub.tars_entity.glossary_parent_node_urn",
        "displayName": "Glossary parent node URN",
        "description": (
            "Optional glossary node for term creation, e.g. urn:li:glossaryNode:fintech. "
            "Defaults to the domain node when omitted."
        ),
        "cardinality": "SINGLE",
    },
    # Operational SPs written by the TARS sync pipeline
    {
        "qualifiedName": "br.com.quintoandar.datahub.tars_entity.data_product_urn",
        "displayName": "Data Product URN",
        "description": "DataHub URN of the Data Product derived from this document, e.g. urn:li:dataProduct:collections.",
        "cardinality": "SINGLE",
    },
    {
        "qualifiedName": "br.com.quintoandar.datahub.tars_entity.sync_status",
        "displayName": "Sync status",
        "description": "Last sync pipeline result: PASS or FAIL.",
        "cardinality": "SINGLE",
    },
    {
        "qualifiedName": "br.com.quintoandar.datahub.tars_entity.sync_error",
        "displayName": "Sync error",
        "description": "Error message from the last sync pipeline run, if any.",
        "cardinality": "SINGLE",
    },
    {
        "qualifiedName": "br.com.quintoandar.datahub.tars_entity.last_synced_at",
        "displayName": "Last synced at",
        "description": "ISO-8601 UTC timestamp of the last successful sync pipeline run.",
        "cardinality": "SINGLE",
    },
    {
        "qualifiedName": "br.com.quintoandar.datahub.tars_entity.last_validated_at",
        "displayName": "Last validated at",
        "description": "ISO-8601 UTC timestamp of the last validation check.",
        "cardinality": "SINGLE",
    },
    {
        "qualifiedName": "br.com.quintoandar.datahub.tars_entity.managed_by",
        "displayName": "Managed by",
        "description": "Team or service that manages this TARS entity.",
        "cardinality": "SINGLE",
    },
]

_CREATE_STRUCTURED_PROPERTY = """
mutation CreateTarsDocumentStructuredProperty($input: CreateStructuredPropertyInput!) {
  createStructuredProperty(input: $input) {
    urn
  }
}
"""

_UPDATE_STRUCTURED_PROPERTY = """
mutation UpdateTarsDocumentStructuredProperty($input: UpdateStructuredPropertyInput!) {
  updateStructuredProperty(input: $input) {
    urn
  }
}
"""

# Settings fields vary by DataHub version — only include fields that exist in this schema.
# showInColumnsTable and showInSearchFilters are absent in some versions; omitting them
# avoids validation errors while still enabling sidebar visibility.
_SETTINGS: dict[str, Any] = {
    "isHidden": False,
    "showInAssetSummary": True,
    "hideInAssetSummaryWhenEmpty": False,
    "showAsAssetBadge": False,
}


def _post(query: str, variables: dict[str, Any]) -> Optional[dict[str, Any]]:
    root, _diag = datahub_graphql_post(GRAPHQL_URL, TOKEN, query, variables)
    if root is None:
        return None
    if root.get("errors"):
        return root
    return root.get("data")


def _already_exists(errors: list[Any]) -> bool:
    for err in errors or []:
        msg = (err.get("message") or "").lower()
        if "already exists" in msg or "duplicate" in msg:
            return True
    return False


def _ensure_entity_types(qname: str, display_name: str, description: str) -> bool:
    """Update an existing property to ensure entity types and settings are applied."""
    urn = f"urn:li:structuredProperty:{qname}"
    result = _post(
        _UPDATE_STRUCTURED_PROPERTY,
        {
            "input": {
                "urn": urn,
                "displayName": display_name,
                "description": description,
                "newEntityTypes": [DOCUMENT_ENTITY_TYPE],
                "settings": _SETTINGS,
            }
        },
    )
    if result is None:
        print(f"  ✗ {qname}: update HTTP/network failure", file=sys.stderr)
        return False
    if isinstance(result, dict) and result.get("errors"):
        print(
            f"  ✗ {qname}: update error {json.dumps(result['errors'])}", file=sys.stderr
        )
        return False
    print(f"  ✓ {qname}: already existed — entity type + settings updated")
    return True


def register_property(spec: dict[str, Any]) -> bool:
    qname = spec["qualifiedName"]
    display_name = spec["displayName"]
    description = spec["description"]
    inp: dict[str, Any] = {
        "qualifiedName": qname,
        "id": qname,
        "displayName": display_name,
        "description": description,
        "valueType": STRING_VALUE_TYPE,
        "cardinality": spec.get("cardinality", "SINGLE"),
        "entityTypes": [DOCUMENT_ENTITY_TYPE],
        "settings": _SETTINGS,
    }
    result = _post(_CREATE_STRUCTURED_PROPERTY, {"input": inp})
    if result is None:
        print(f"  ✗ {qname}: HTTP/network failure", file=sys.stderr)
        return False
    if isinstance(result, dict) and result.get("errors"):
        if _already_exists(result["errors"]):
            # Property exists but may lack entityTypes — always run update to ensure it.
            return _ensure_entity_types(qname, display_name, description)
        print(f"  ✗ {qname}: {json.dumps(result['errors'])}", file=sys.stderr)
        return False
    created = (result or {}).get("createStructuredProperty") or {}
    urn = created.get("urn")
    if urn:
        print(f"  ✓ {qname} → {urn}")
        return True
    print(f"  ✗ {qname}: unexpected response {result}", file=sys.stderr)
    return False


def main() -> int:
    if not GRAPHQL_URL:
        print("ERROR: DATAHUB_GRAPHQL_URL is not set.", file=sys.stderr)
        return 1

    print(f"DataHub target: {GRAPHQL_URL}")
    print(
        f"Registering {len(TARS_DOCUMENT_PROPERTIES)} structured properties on DOCUMENT entities…"
    )

    ok = 0
    failed = 0
    for spec in TARS_DOCUMENT_PROPERTIES:
        if register_property(spec):
            ok += 1
        else:
            failed += 1

    print(f"\nDone: {ok} ok, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
