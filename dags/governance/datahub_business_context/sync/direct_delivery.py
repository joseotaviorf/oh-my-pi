"""Direct delivery: push YAML to DataHub and backlink Data Product to source document (Option B)."""

from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

from sync.datahub_client import post as _dh_post

SCRIPT_DIR = Path(__file__).resolve().parent.parent
LOADER = SCRIPT_DIR / "load_collections_context.py"


@dataclass
class DirectPushResult:
    data_product_urn: str
    loader_exit_code: int
    backlink_ok: bool


_UPDATE_DOCUMENT_RELATED_ENTITIES = """
mutation UpdateDocumentRelatedEntities($input: UpdateDocumentRelatedEntitiesInput!) {
  updateDocumentRelatedEntities(input: $input)
}
"""

_FETCH_DOCUMENT_RELATED_ASSETS = """
query FetchDocumentRelatedAssets($urn: String!) {
  document(urn: $urn) {
    relatedEntities {
      relatedAssets {
        urn
      }
    }
  }
}
"""


def _post(query: str, variables: dict[str, Any]) -> Optional[dict[str, Any]]:
    return _dh_post(query, variables)


def _normalize_data_product_id(data_product_id: str) -> str:
    return data_product_id.strip().lower().replace("_", "-")


def push_yaml_to_datahub(yaml_path: Path) -> int:
    """Invoke ``load_collections_context.py`` for a generated YAML file."""
    proc = subprocess.run(
        [sys.executable, str(LOADER), "--config", str(yaml_path)],
        check=False,
    )
    return int(proc.returncode)


def _fetch_existing_related_assets(document_urn: str) -> list[str]:
    data = _post(_FETCH_DOCUMENT_RELATED_ASSETS, {"urn": document_urn})
    if not data:
        return []
    doc = data.get("document") or {}
    related = doc.get("relatedEntities") or {}
    assets = related.get("relatedAssets") or []
    urns: list[str] = []
    for asset in assets:
        urn = asset.get("urn")
        if urn:
            urns.append(str(urn))
    return urns


def backlink_data_product_to_document(
    document_urn: str,
    data_product_urn: str,
) -> bool:
    """Attach the derived Data Product as a related asset on the source document."""
    existing = _fetch_existing_related_assets(document_urn)
    merged = list(dict.fromkeys([*existing, data_product_urn]))
    data = _post(
        _UPDATE_DOCUMENT_RELATED_ENTITIES,
        {
            "input": {
                "urn": document_urn,
                "relatedAssets": merged,
            }
        },
    )
    if data is None:
        return False
    return data.get("updateDocumentRelatedEntities") is not False


def deliver_direct(
    yaml_path: Path,
    *,
    document_urn: str,
    data_product_id: str,
) -> DirectPushResult:
    """Push YAML via GraphQL loader and backlink the Data Product to the document."""
    product_id = _normalize_data_product_id(data_product_id)
    exit_code = push_yaml_to_datahub(yaml_path)
    dp_urn = f"urn:li:dataProduct:{product_id}"
    backlink_ok = False
    if exit_code == 0:
        backlink_ok = backlink_data_product_to_document(document_urn, dp_urn)
    return DirectPushResult(
        data_product_urn=dp_urn,
        loader_exit_code=exit_code,
        backlink_ok=backlink_ok,
    )
