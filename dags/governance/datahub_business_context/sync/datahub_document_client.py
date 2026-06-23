"""DataHub GraphQL client for discovering and fetching TARS entity Context Documents."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional

from sync.constants import (
    DATA_PRODUCT_TYPE_DOMAIN,
    DATA_PRODUCT_TYPE_METRIC,
    STRUCTURED_PROP_DATA_PRODUCT_ID,
    STRUCTURED_PROP_DOMAIN_URN,
    STRUCTURED_PROP_GLOSSARY_PARENT,
    STRUCTURED_PROP_GOLDEN_QUERY_URN,
    STRUCTURED_PROP_PRIMARY_DATASETS,
    STRUCTURED_PROP_SYNC_STATUS,
    TARS_ENTITY_TAG,
    TARS_METRICS_TAG,
)
from sync.datahub_client import post as _dh_post


@dataclass
class TarsEntityDocument:
    urn: str
    title: str
    content: str
    last_modified_ms: Optional[int] = None
    domain_urn: str = ""
    data_product_id: str = ""
    primary_datasets: list[tuple[str, str]] = field(default_factory=list)
    golden_query_stable_urn: str = ""
    glossary_parent_node_urn: str = ""
    is_published: bool = False
    data_product_type: str = DATA_PRODUCT_TYPE_DOMAIN


_SEARCH_DOCUMENTS = """
query SearchTarsEntityDocuments($input: SearchInput!) {
  search(input: $input) {
    total
    searchResults {
      entity {
        urn
        ... on Document {
          info {
            title
            status { state }
            contents { text }
          }
          tags {
            tags {
              tag {
                name
              }
            }
          }
          domain {
            domain {
              urn
            }
          }
          structuredProperties {
            properties {
              structuredProperty {
                definition {
                  qualifiedName
                }
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
    }
  }
}
"""

_GET_DOCUMENT = """
query GetTarsEntityDocument($urn: String!) {
  document(urn: $urn) {
    urn
    info {
      title
      status { state }
      contents { text }
    }
    tags {
      tags {
        tag {
          name
        }
      }
    }
    domain {
      domain {
        urn
      }
    }
    structuredProperties {
      properties {
        structuredProperty {
          definition {
            qualifiedName
          }
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


def _post(query: str, variables: dict[str, Any]) -> Optional[dict[str, Any]]:
    return _dh_post(query, variables)


def _string_prop(props: dict[str, str], qname: str) -> str:
    return props.get(qname, "").strip()


def _parse_structured_properties(entity: dict[str, Any]) -> dict[str, str]:
    out: dict[str, str] = {}
    sp = entity.get("structuredProperties") or {}
    for prop in sp.get("properties") or []:
        sp_def = (prop.get("structuredProperty") or {}).get("definition") or {}
        qname = sp_def.get("qualifiedName") or ""
        values = prop.get("values") or []
        for val in values:
            sv = val.get("stringValue")
            if sv is not None and qname:
                out[qname] = str(sv)
    return out


def _extract_content(entity: dict[str, Any]) -> str:
    info = entity.get("info") or {}
    return ((info.get("contents") or {}).get("text") or "").strip()


def _parse_primary_datasets(raw: str) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    for part in raw.split(","):
        part = part.strip()
        if "." in part:
            schema, table = part.split(".", 1)
            pairs.append((schema.strip(), table.strip()))
    return pairs


def _extract_product_type_from_tags(entity: dict[str, Any]) -> Optional[str]:
    """Return DATA_PRODUCT_TYPE_DOMAIN/METRIC if a tars tag is present, else None."""
    tag_names = {
        (t.get("tag") or {}).get("name") or ""
        for t in ((entity.get("tags") or {}).get("tags") or [])
    }
    if TARS_METRICS_TAG in tag_names:
        return DATA_PRODUCT_TYPE_METRIC
    if TARS_ENTITY_TAG in tag_names:
        return DATA_PRODUCT_TYPE_DOMAIN
    return None


def _entity_to_document(entity: dict[str, Any]) -> Optional[TarsEntityDocument]:
    if not entity or not entity.get("urn"):
        return None
    product_type = _extract_product_type_from_tags(entity)
    if product_type is None:
        return None
    info = entity.get("info") or {}
    state = ((info.get("status") or {}).get("state") or "").upper()
    is_published = state == "PUBLISHED"
    props = _parse_structured_properties(entity)
    title = info.get("title") or "Untitled"
    domain_blob = entity.get("domain") or {}
    domain_urn = ((domain_blob.get("domain") or {}).get("urn")) or _string_prop(
        props, STRUCTURED_PROP_DOMAIN_URN
    )
    content = _extract_content(entity)
    return TarsEntityDocument(
        urn=str(entity["urn"]),
        title=str(title).strip(),
        content=content,
        domain_urn=domain_urn,
        data_product_id=_string_prop(props, STRUCTURED_PROP_DATA_PRODUCT_ID),
        primary_datasets=_parse_primary_datasets(
            _string_prop(props, STRUCTURED_PROP_PRIMARY_DATASETS)
        ),
        golden_query_stable_urn=_string_prop(props, STRUCTURED_PROP_GOLDEN_QUERY_URN),
        glossary_parent_node_urn=_string_prop(props, STRUCTURED_PROP_GLOSSARY_PARENT),
        is_published=is_published,
        data_product_type=product_type,
    )


_UPSERT_STRUCTURED_PROPERTIES = """
mutation UpsertStructuredProperties($input: UpsertStructuredPropertiesInput!) {
  upsertStructuredProperties(input: $input) {
    properties {
      structuredProperty { urn }
    }
  }
}
"""

_FETCH_DOCUMENT_STRUCTURED_PROPERTIES = """
query FetchDocumentStructuredProperties($urn: String!) {
  document(urn: $urn) {
    structuredProperties {
      properties {
        structuredProperty { urn }
        values {
          ... on StringValue { stringValue }
          ... on NumberValue { numberValue }
        }
      }
    }
  }
}
"""


_GET_DATA_PRODUCT = """
query ClassifyDataProduct($urn: String!) {
  dataProduct(urn: $urn) {
    urn
    properties { name }
  }
}
"""


def fetch_data_product(dp_urn: str) -> Optional[dict[str, Any]]:
    """Return the DataHub Data Product dict if it exists, else None."""
    data = _dh_post(_GET_DATA_PRODUCT, {"urn": dp_urn})
    dp = (data or {}).get("dataProduct")
    return dp if dp and dp.get("properties") else None


def _structured_property_rows_from_fetch(
    fetch_data: dict[str, Any],
    *,
    skip_sp_urns: frozenset[str] = frozenset(),
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for prop in fetch_data.get("properties") or []:
        sp_u = (prop.get("structuredProperty") or {}).get("urn") or ""
        if not sp_u or sp_u in skip_sp_urns:
            continue
        converted: list[dict[str, Any]] = []
        for val in prop.get("values") or []:
            if val.get("stringValue") is not None:
                converted.append({"stringValue": val["stringValue"]})
            elif val.get("numberValue") is not None:
                converted.append({"numberValue": val["numberValue"]})
        if converted:
            rows.append({"structuredPropertyUrn": sp_u, "values": converted})
    return rows


def _upsert_document_structured_properties(
    doc_urn: str,
    updates: dict[str, str],
) -> bool:
    """Merge existing document structured properties with ``updates`` (qname → value)."""
    skip_urns = frozenset(f"urn:li:structuredProperty:{qn}" for qn in updates)
    fetch = _post(_FETCH_DOCUMENT_STRUCTURED_PROPERTIES, {"urn": doc_urn})
    merged: list[dict[str, Any]] = []
    if fetch is not None:
        doc_blob = fetch.get("document") or {}
        sp_blob = doc_blob.get("structuredProperties") or {}
        merged = _structured_property_rows_from_fetch(
            sp_blob,
            skip_sp_urns=skip_urns,
        )
    for qn, value in updates.items():
        merged.append(
            {
                "structuredPropertyUrn": f"urn:li:structuredProperty:{qn}",
                "values": [{"stringValue": value}],
            }
        )
    data = _post(
        _UPSERT_STRUCTURED_PROPERTIES,
        {
            "input": {
                "assetUrn": doc_urn,
                "structuredPropertyInputParams": merged,
            }
        },
    )
    return data is not None


def write_data_product_id(doc_urn: str, data_product_id: str) -> bool:
    """Write data_product_id back to the Context Document structured-property sidebar."""
    return _upsert_document_structured_properties(
        doc_urn,
        {STRUCTURED_PROP_DATA_PRODUCT_ID: data_product_id},
    )


def write_golden_query_urn(doc_urn: str, stable_urn: str) -> bool:
    """Write the auto-generated golden query URN back onto the document so future syncs reuse it."""
    return _upsert_document_structured_properties(
        doc_urn,
        {STRUCTURED_PROP_GOLDEN_QUERY_URN: stable_urn},
    )


def write_sync_status(
    doc_urn: str,
    *,
    status: str,
    data_product_urn: str = "",
    error: str = "",
) -> bool:
    """Write sync outcome back to the Context Document structured-property sidebar.

    ``status`` should be ``"PASS"`` or ``"FAIL"``.  On failure, ``error`` is
    appended so the author can see why directly in the DataHub UI.

    Requires the ``br.com.quintoandar.datahub.tars_entity.sync_status``
    structured property to exist in DataHub (create it once via the UI or API).
    """
    value = status
    if error:
        value = f"{status}: {error}"
    updates: dict[str, str] = {STRUCTURED_PROP_SYNC_STATUS: value}
    if data_product_urn:
        updates[STRUCTURED_PROP_DATA_PRODUCT_ID] = data_product_urn.split(":")[-1]
    return _upsert_document_structured_properties(doc_urn, updates)


def _search_documents_by_tag(
    tag: str,
    *,
    count: int = 50,
) -> list[TarsEntityDocument]:
    """Paginate all Context Documents tagged ``tag`` and return parsed documents."""
    query_string = f"tags:{tag}"
    docs: list[TarsEntityDocument] = []
    start = 0
    total: Optional[int] = None

    while True:
        data = _post(
            _SEARCH_DOCUMENTS,
            {
                "input": {
                    "type": "DOCUMENT",
                    "query": query_string,
                    "start": start,
                    "count": count,
                }
            },
        )
        if not data:
            break
        search_blob = data.get("search") or {}
        if total is None:
            total = int(search_blob.get("total") or 0)
        results = search_blob.get("searchResults") or []
        if not results:
            break
        for row in results:
            entity = row.get("entity") or {}
            doc = _entity_to_document(entity)
            if doc and doc.content:
                docs.append(doc)
        start += len(results)
        if len(results) < count or (total is not None and start >= total):
            break

    return docs


def search_tars_entity_documents(
    *,
    count: int = 50,
) -> list[TarsEntityDocument]:
    """Search Context Documents tagged ``tars-entity`` or ``tars-metrics`` (paginated).

    Both tags are searched separately to avoid relying on DataHub OR-query syntax.
    Results are deduplicated by URN.
    """
    docs: list[TarsEntityDocument] = []
    seen_urns: set[str] = set()
    for tag in (TARS_ENTITY_TAG, TARS_METRICS_TAG):
        for doc in _search_documents_by_tag(tag, count=count):
            if doc.urn not in seen_urns:
                seen_urns.add(doc.urn)
                docs.append(doc)
    return docs


def fetch_document(urn: str) -> Optional[TarsEntityDocument]:
    data = _post(_GET_DOCUMENT, {"urn": urn})
    if not data:
        return None
    entity = data.get("document") or {}
    return _entity_to_document(entity)
