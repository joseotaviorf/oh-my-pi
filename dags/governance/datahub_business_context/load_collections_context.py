"""Push curated business context into DataHub via GraphQL mutations.

**Configuration is YAML-first** (``spec_version: 1``, ``kind: data_product_curated_entity``).
Use ``--config`` to choose a preset file:

    python .../load_collections_context.py \\
      --config .../datahub_entities/collections-recovery.datahub.yaml

    python .../load_collections_context.py \\
      --config .../datahub_entities/customer-support-contacts.datahub.yaml

Each YAML preset declares: ``product_display_name``, ``product_description``,
``data_product_id``, ``domain_urn``, ``structured_property``, ``golden_query``
(with ``stable_urn``, ``name``, ``description``, ``subjects``, ``sql``),
``datasets`` (each entry may carry ``description`` and ``fields`` for per-dataset/field
descriptions), ``glossary_terms``, and ``documentation_link``.

Usage:
    export DATAHUB_GRAPHQL_URL=https://<your-datahub-host>/api/graphql
    export DATAHUB_TOKEN=<personal-access-token-with-editor-role>
    # Optional: Habitat UI origin used when removing stale discovery links
    # export DATAHUB_UI_ORIGIN=https://datahub.apps.data-prd.habitat.zone

The mutations are written to be safe to retry: descriptions are upserts; creates are
best-effort with duplicate handling.

Exit codes: 0 = success; 1 = at least one step failed (see stderr).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Optional

import yaml

# ---------------------------------------------------------------------------
# Bootstrap: reuse the existing GraphQL client from bietlejuice
# ---------------------------------------------------------------------------

# Allow running from repo root without installing the package (runtime code lives
# under packages/bietlejuice-runtime/src on post-split layouts).
_repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
_runtime_src = os.path.join(_repo_root, "packages", "bietlejuice-runtime", "src")
for _p in (_runtime_src, _repo_root):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from datahub_curated_urns import (  # noqa: E402
    STRUCTURED_PROPERTY_ENTITY_TYPE_DATA_PRODUCT,
    STRUCTURED_PROPERTY_ENTITY_TYPE_QUERY,
    STRUCTURED_PROPERTY_VALUE_TYPE_URN_POINTER,
    structured_property_urn,
)

from bietlejuice.governance.fairness_assessment.datahub_graphql.client import (  # noqa: E402
    datahub_graphql_post,
)

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

SPEC_VERSION_EXPECTED = 1
KIND_DATA_PRODUCT_CURATED_ENTITY = "data_product_curated_entity"

_SCRIPT_DIR = Path(__file__).resolve().parent
_DATAHUB_ENTITY_CONFIG_DIR = _SCRIPT_DIR / "datahub_entities"
DEFAULT_CONFIG_PATH = _DATAHUB_ENTITY_CONFIG_DIR / "collections-recovery.datahub.yaml"

GRAPHQL_URL = os.environ.get("DATAHUB_GRAPHQL_URL", "").strip()
TOKEN: Optional[str] = os.environ.get("DATAHUB_TOKEN", "").strip() or None

PLATFORM = "databricks"

# Fallback anchors when YAML omits domain/glossary (presets normally set explicitly).
_FALLBACK_DOMAIN_URN = "urn:li:domain:fintech"
_FALLBACK_GLOSSARY_PARENT_NODE_URN = "urn:li:glossaryNode:fintech"


DATAHUB_UI_ORIGIN = os.environ.get(
    "DATAHUB_UI_ORIGIN", "https://datahub.apps.data-prd.habitat.zone"
).rstrip("/")


def load_yaml_spec(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf8") as fh:
        spec = yaml.safe_load(fh)
    if not isinstance(spec, dict):
        raise SystemExit(f"YAML spec must be a mapping: {path}")
    return spec


def _ensure_spec_supported(spec: dict[str, Any], path: Path) -> None:
    if spec.get("spec_version") != SPEC_VERSION_EXPECTED:
        raise SystemExit(
            f"{path}: unsupported spec_version (expected {SPEC_VERSION_EXPECTED})",
        )


def _urn(schema: str, table: str) -> str:
    return f"urn:li:dataset:(urn:li:dataPlatform:{PLATFORM},{schema}.{table},PROD)"


# ---------------------------------------------------------------------------
# GraphQL helpers
# ---------------------------------------------------------------------------

_errors: list[str] = []


def _post(query: str, variables: dict[str, Any]) -> Optional[dict[str, Any]]:
    if not GRAPHQL_URL:
        raise RuntimeError(
            "DATAHUB_GRAPHQL_URL is not set. Export it before running this script."
        )
    root, diag = datahub_graphql_post(GRAPHQL_URL, TOKEN, query, variables)
    if root is None:
        print(f"    [DEBUG] HTTP-level failure, diag={diag}", file=sys.stderr)
        return None
    gql_errors = root.get("errors")
    if gql_errors:
        print(f"    [DEBUG] GraphQL errors: {json.dumps(gql_errors)}", file=sys.stderr)
        return None
    return root.get("data")


def _ok(label: str, data: Any = None) -> None:
    print(f"  \u2713 {label}")


def _fail(label: str, detail: str) -> None:
    msg = f"  \u2717 {label}: {detail}"
    print(msg, file=sys.stderr)
    _errors.append(msg)


def _graphql_root(query: str, variables: dict[str, Any]) -> Optional[dict]:
    """Returns the full GraphQL JSON body (possibly with ``errors``) or None on HTTP failure."""
    root, diag = datahub_graphql_post(GRAPHQL_URL, TOKEN, query, variables)
    if root is None:
        print(f"    [DEBUG] HTTP-level failure, diag={diag}", file=sys.stderr)
    return root


def _errors_indicate_already_exists(errors: list) -> bool:
    for err in errors or []:
        lower = (err.get("message") or "").lower()
        if "already exists" in lower or "duplicate" in lower or "duplicatekey" in lower:
            return True
    return False


# ---------------------------------------------------------------------------
# Mutation 1 — Dataset descriptions
# ---------------------------------------------------------------------------

_UPDATE_DATASET_DESCRIPTION = """
mutation UpdateDatasetDescription($urn: String!, $description: String!) {
  updateDataset(urn: $urn, input: {
    editableProperties: { description: $description }
  }) {
    urn
  }
}
"""


# ---------------------------------------------------------------------------
# Mutation 2 — schemaField descriptions
# ---------------------------------------------------------------------------

_UPDATE_FIELD_DESCRIPTION = """
mutation UpdateFieldDescription(
  $description: String!,
  $resourceUrn: String!,
  $fieldPath: String!
) {
  updateDescription(input: {
    description: $description,
    resourceUrn: $resourceUrn,
    subResource: $fieldPath,
    subResourceType: DATASET_FIELD
  })
}
"""


# ---------------------------------------------------------------------------
# Mutation 3 — Glossary terms
# ---------------------------------------------------------------------------

# createGlossaryTerm returns a plain String (the URN), not an object.
_CREATE_GLOSSARY_TERM = """
mutation CreateGlossaryTerm($input: CreateGlossaryEntityInput!) {
  createGlossaryTerm(input: $input)
}
"""

_SEARCH_GLOSSARY_TERM = """
query SearchGlossaryTerm($id: String!) {
  glossaryTerm(urn: $urn) {
    urn
  }
}
"""


def _glossary_term_urn(term_id: str) -> str:
    return f"urn:li:glossaryTerm:{term_id}"


def _term_exists(term_id: str) -> bool:
    """Check whether a glossary term already exists by querying its URN directly.

    Previous approach used text-search with count=5, which fails for short or
    common IDs (e.g. 'csat') that don't surface in the top search results.
    Direct lookup is reliable: DataHub returns a non-null shell for any URN, but
    only real terms have a non-null `properties` block.
    """
    query = """
    query CheckGlossaryTermExists($urn: String!) {
      glossaryTerm(urn: $urn) {
        properties { name }
      }
    }
    """
    urn = _glossary_term_urn(term_id)
    data = _post(query, {"urn": urn})
    if not data:
        return False
    term = data.get("glossaryTerm") or {}
    return bool(term.get("properties"))


def _push_term_related_terms(
    source_urn: str,
    related_terms_cfg: list[dict[str, str]],
) -> None:
    """Wire DataHub Glossary Related Term relationships for a single term.

    Each entry in *related_terms_cfg* is a dict with:
      ``urn``          – the other glossary term's URN
      ``relationship`` – one of: isA | inherits | inherited_by | hasA | contains | contained_by

    For ``contained_by`` / ``inherited_by`` the source/target are swapped so that
    the relationship is always declared on the semantically correct owner side.
    """
    for entry in related_terms_cfg:
        other_urn = str(entry.get("urn") or "").strip()
        rel_key = str(entry.get("relationship") or "").strip()
        if not other_urn or not rel_key:
            _fail(
                f"related_term for {source_urn}",
                f"missing 'urn' or 'relationship' in entry: {entry}",
            )
            continue

        gql_type = _RELATIONSHIP_TYPE_MAP.get(rel_key)
        if gql_type is None:
            _fail(
                f"related_term for {source_urn}",
                f"unknown relationship {rel_key!r}; "
                f"valid: {sorted(_RELATIONSHIP_TYPE_MAP)}",
            )
            continue

        if rel_key in _REVERSE_RELATIONSHIP_KEYS:
            mutation_source, mutation_targets = other_urn, [source_urn]
        else:
            mutation_source, mutation_targets = source_urn, [other_urn]

        label = f"{source_urn} --[{rel_key}]--> {other_urn}"
        data = _post(
            _ADD_RELATED_TERMS,
            {
                "input": {
                    "urn": mutation_source,
                    "termUrns": mutation_targets,
                    "relationshipType": gql_type,
                }
            },
        )
        if data is not None and data.get("addRelatedTerms") is not False:
            _ok(f"Related term: {label}")
        else:
            _fail(f"addRelatedTerms {label}", f"unexpected response: {data}")


# ---------------------------------------------------------------------------
# Mutation 4 — DataProduct
# ---------------------------------------------------------------------------

_CREATE_DATA_PRODUCT = """
mutation CreateDataProduct($input: CreateDataProductInput!) {
  createDataProduct(input: $input) {
    urn
  }
}
"""

_SET_DATA_PRODUCT_ASSETS = """
mutation BatchSetDataProductAssets($input: BatchSetDataProductInput!) {
  batchSetDataProduct(input: $input)
}
"""

_CHECK_DATA_PRODUCT = """
query CheckDataProduct($urn: String!) {
  dataProduct(urn: $urn) { urn }
}
"""


def _data_product_urn(product_id: str) -> str:
    return f"urn:li:dataProduct:{product_id}"


# ---------------------------------------------------------------------------
# Mutation 4b — DataProduct enrichments (glossary terms + GitHub resource)
# ---------------------------------------------------------------------------

_ADD_LINK = """
mutation AddLink($input: AddLinkInput!) {
  addLink(input: $input)
}
"""

_BATCH_ADD_TERMS = """
mutation BatchAddTerms($input: BatchAddTermsInput!) {
  batchAddTerms(input: $input)
}
"""

_ADD_RELATED_TERMS = """
mutation AddRelatedTerms($input: RelatedTermsInput!) {
  addRelatedTerms(input: $input)
}
"""

# Maps human-friendly YAML values to the DataHub TermRelationshipType enum.
# DataHub exposes only two enum values: isA and hasA.
# "contained_by" and "inherited_by" are inverse views — handled by swapping
# source / target in the mutation call (see _REVERSE_RELATIONSHIP_KEYS).
_RELATIONSHIP_TYPE_MAP: dict[str, str] = {
    "isA": "isA",
    "inherits": "isA",
    "inherited_by": "isA",
    "hasA": "hasA",
    "contains": "hasA",
    "contained_by": "hasA",
}
_REVERSE_RELATIONSHIP_KEYS = frozenset({"inherited_by", "contained_by"})


# ---------------------------------------------------------------------------
# Mutation 6 — Golden query
# ---------------------------------------------------------------------------

_CREATE_QUERY = """
mutation CreateQuery($input: CreateQueryInput!) {
  createQuery(input: $input) {
    urn
  }
}
"""


_SEARCH_QUERIES = """
query DhSearchQueries($frag: String!) {
  search(
    input: { query: $frag, type: QUERY, start: 0, count: 35 }
  ) {
    searchResults {
      entity {
        urn
      }
    }
  }
}
"""


_REMOVE_LINK = """
mutation RemoveGoldenQueryLink($input: RemoveLinkInput!) {
  removeLink(input: $input)
}
"""


# ---------------------------------------------------------------------------
# Mutation 7 — Golden query structured property (Data Product sidebar)
# ---------------------------------------------------------------------------
# upsertStructuredProperties replaces all structured properties on the asset;
# we pre-fetch existing properties and merge so sibling keys are preserved.

_FETCH_DATA_PRODUCT_STRUCTURED_PROPERTIES = """
query FetchDataProductStructuredProperties($urn: String!) {
  dataProduct(urn: $urn) {
    urn
    structuredProperties {
      properties {
        structuredProperty {
          urn
        }
        values {
          ... on StringValue {
            stringValue
          }
          ... on NumberValue {
            numberValue
          }
        }
        valueEntities {
          urn
        }
      }
    }
  }
}
"""

_CREATE_STRUCTURED_PROPERTY = """
mutation CreateStructuredPropertyGoldenQuery($input: CreateStructuredPropertyInput!) {
  createStructuredProperty(input: $input) {
    urn
  }
}
"""

_UPSERT_STRUCTURED_PROPERTIES = """
mutation UpsertStructuredPropertiesGoldenQuery($input: UpsertStructuredPropertiesInput!) {
  upsertStructuredProperties(input: $input) {
    properties {
      structuredProperty {
        urn
      }
    }
  }
}
"""


def _structured_property_entry_to_value_inputs(
    prop: dict[str, Any],
) -> Optional[list[dict[str, Any]]]:
    """Rebuild PropertyValueInput rows for merge (string/number union and/or resolved URN entities)."""

    values = prop.get("values") or []
    value_entities = prop.get("valueEntities") or []

    out: list[dict[str, Any]] = []
    saw_unsupported_value = False
    for raw in values:
        if not isinstance(raw, dict):
            return None
        if raw.get("stringValue") is not None:
            out.append({"stringValue": raw["stringValue"]})
        elif raw.get("numberValue") is not None:
            out.append({"numberValue": raw["numberValue"]})
        elif not any(v is not None for v in raw.values()):
            continue
        else:
            saw_unsupported_value = True
            break

    if saw_unsupported_value:
        out = []

    if out:
        return out

    for ent in value_entities:
        if not isinstance(ent, dict):
            return None
        urn = ent.get("urn")
        if not urn:
            return None
        out.append({"stringValue": urn})

    return out if out else None


def _duplicate_structured_property_message(errors: list[Any]) -> bool:
    """Treat createStructuredProperty duplicates as success (definition already present)."""

    for err in errors or []:
        msg = (err.get("message") or "").lower()
        if "duplicate" in msg and "structured" in msg:
            return True
        if "already exists" in msg and ("property" in msg or "qualified" in msg):
            return True
    return False


def ensure_dp_golden_struct_property(qualified_name: str) -> None:
    """Idempotent CreateStructuredProperty: URN type restricted to Query."""

    inp: dict[str, Any] = {
        "qualifiedName": qualified_name,
        "id": qualified_name,
        "displayName": "Golden query",
        "description": (
            "Canonical validated SQL for this Data Product, stored as a Query entity "
            "(navigable from the sidebar)."
        ),
        "valueType": STRUCTURED_PROPERTY_VALUE_TYPE_URN_POINTER,
        "typeQualifier": {"allowedTypes": [STRUCTURED_PROPERTY_ENTITY_TYPE_QUERY]},
        "cardinality": "SINGLE",
        "entityTypes": [STRUCTURED_PROPERTY_ENTITY_TYPE_DATA_PRODUCT],
        "settings": {
            "showInAssetSummary": True,
            "hideInAssetSummaryWhenEmpty": True,
            "showInSearchFilters": False,
            "isHidden": False,
            "showAsAssetBadge": False,
            "showInColumnsTable": False,
        },
    }
    root = _graphql_root(_CREATE_STRUCTURED_PROPERTY, {"input": inp})
    if root is None:
        _fail(
            "createStructuredProperty (golden query)",
            "HTTP/network failure calling GraphQL",
        )
        return
    gql_errors = root.get("errors")
    if gql_errors:
        if _errors_indicate_already_exists(
            gql_errors
        ) or _duplicate_structured_property_message(gql_errors):
            _ok(f"Structured property already defined ({qualified_name})")
            return
        _fail(
            "createStructuredProperty (golden query)",
            json.dumps(gql_errors),
        )
        return
    data = root.get("data") or {}
    created = data.get("createStructuredProperty")
    urn_resp = created.get("urn") if isinstance(created, dict) else None
    if urn_resp:
        _ok(f"Defined structured property {urn_resp}")
    else:
        _fail(
            "createStructuredProperty (golden query)",
            f"unexpected response: {data}",
        )


def _merged_dp_structured_props(
    dp_urn: str,
    *,
    golden_sp_qname: str,
    golden_query_urn_val: str,
    legacy_skip_urns: Optional[frozenset[str]] = None,
) -> Optional[list[dict[str, Any]]]:
    """Merge existing Data Product structured properties with golden-query sidebar entry."""

    golden_sp_urn = structured_property_urn(golden_sp_qname)
    our_row = {
        "structuredPropertyUrn": golden_sp_urn,
        "values": [{"stringValue": golden_query_urn_val}],
    }
    legacy_skip = set(legacy_skip_urns or frozenset())
    fetch = _post(_FETCH_DATA_PRODUCT_STRUCTURED_PROPERTIES, {"urn": dp_urn})
    if fetch is None:
        print(
            "    Prefetch structured properties failed (GraphQL errors or HTTP failure).",
            file=sys.stderr,
        )
        return None
    dp_blob = fetch.get("dataProduct")
    if dp_blob is None:
        print(
            "    dataProduct(...) returned null — cannot merge structured properties.",
            file=sys.stderr,
        )
        return None

    props = (
        ((dp_blob.get("structuredProperties") or {}).get("properties")) or []
    ) or []
    if not props:
        return [our_row]

    merged: list[dict[str, Any]] = []
    for prop in props:
        sp_blob = prop.get("structuredProperty") or {}
        sp_u = sp_blob.get("urn")
        if not sp_u:
            continue
        if sp_u == golden_sp_urn:
            continue
        if sp_u in legacy_skip:
            q_disp = (
                sp_u.replace("urn:li:structuredProperty:", "", 1)
                if "structuredProperty:" in sp_u
                else sp_u
            )
            print(
                "    Dropping legacy structured property from Data Product merge "
                f"({q_disp}).",
                file=sys.stderr,
            )
            continue
        converted = _structured_property_entry_to_value_inputs(prop)
        if converted is None:
            print(
                f"    Cannot merge sibling structured property {sp_u}: "
                "could not round-trip values — use OpenAPI PATCH or remove conflicting "
                "properties before running this loader.",
                file=sys.stderr,
            )
            return None
        merged.append({"structuredPropertyUrn": sp_u, "values": converted})

    merged.append(our_row)
    return merged


# ---------------------------------------------------------------------------
# Curated Entity preset (YAML kind: data_product_curated_entity)
# ---------------------------------------------------------------------------


def _curated_dataset_subject_urns(cfg: dict[str, Any]) -> list[str]:
    gq = cfg.get("golden_query")
    assert isinstance(gq, dict), "golden_query must be a mapping"
    raw_subj = gq.get("subjects") or []
    rows = raw_subj if isinstance(raw_subj, list) else []
    urns = []
    for row in rows:
        if isinstance(row, dict) and row.get("schema") and row.get("table"):
            urns.append(_urn(str(row["schema"]), str(row["table"])))
    if not urns:
        raise SystemExit(
            "`golden_query.subjects` (list of {schema, table}) is required "
            "for data_product_curated_entity",
        )
    return urns


def _curated_data_product_asset_urns(cfg: dict[str, Any]) -> list[str]:
    rows = cfg.get("datasets") or []
    if not isinstance(rows, list) or not rows:
        raise SystemExit("`datasets` (non-empty list) is required")
    out = []
    for row in rows:
        if isinstance(row, dict) and row.get("schema") and row.get("table"):
            out.append(_urn(str(row["schema"]), str(row["table"])))
    return sorted(set(out))


def curated_push_assets(cfg: dict[str, Any]) -> None:
    print("\n[1/7] DataProduct assets (datasets only)...")
    pid = str(cfg["data_product_id"])
    pname = cfg.get("product_display_name") or pid
    pdesc_raw = cfg.get("product_description")
    dom = cfg.get("domain_urn") or _FALLBACK_DOMAIN_URN
    if not isinstance(pdesc_raw, str) or not pdesc_raw.strip():
        raise SystemExit("product_description (non-empty string) is required")

    urns = _curated_data_product_asset_urns(cfg)
    dp_u = _data_product_urn(pid)

    cre = _post(
        _CREATE_DATA_PRODUCT,
        {
            "input": {
                "id": pid,
                "properties": {
                    "name": str(pname),
                    "description": pdesc_raw.strip(),
                },
                "domainUrn": str(dom),
            },
        },
    )
    if cre and cre.get("createDataProduct", {}).get("urn"):
        _ok(f"Created DataProduct ({dp_u})")
    else:
        print("  -> DataProduct create returned empty (probably already exists)")

    ln = _post(
        _SET_DATA_PRODUCT_ASSETS,
        {"input": {"dataProductUrn": dp_u, "resourceUrns": urns}},
    )
    if ln is None:
        _fail("curated.batchSetDataProduct", "mutation failed")
        return
    _ok(f"Linked {len(urns)} datasets")


def curated_push_documentation_link(cfg: dict[str, Any]) -> None:
    print("\n[2/7] Documentation link...")
    dl = cfg.get("documentation_link")
    if not isinstance(dl, dict) or not dl.get("url") or not dl.get("label"):
        print("  -> skipping documentation_link")
        return
    dp_u = _data_product_urn(str(cfg["data_product_id"]))
    root = _graphql_root(
        _ADD_LINK,
        {
            "input": {
                "linkUrl": str(dl["url"]),
                "label": str(dl["label"]),
                "resourceUrn": dp_u,
            },
        },
    )
    errs = (root or {}).get("errors") or []
    data_g = (root or {}).get("data") if not errs else {}
    if data_g and data_g.get("addLink") is not None:
        _ok("Linked documentation")
    elif errs and _errors_indicate_already_exists(errs):
        _ok("Documentation link (already present)")
    else:
        _fail(
            "curated.addLink (documentation)",
            json.dumps(root, default=str),
        )


def curated_push_glossary_terms(cfg: dict[str, Any]) -> None:
    """Create glossary terms declared in the YAML and wire any related-term relationships.

    Skips the step gracefully when the YAML has no ``glossary_terms`` block so that
    existing configs (e.g. datahub_entities/customer-support-contacts.datahub.yaml) keep working
    without any changes.

    After terms are created / verified the function attaches them to the Data Product
    via ``batchAddTerms``.
    """
    print("\n[3/7] Glossary terms...")
    gt_block = cfg.get("glossary_terms")
    if not isinstance(gt_block, dict) or not gt_block.get("terms"):
        print("  -> no glossary_terms block — skipping")
        return

    parent_node = (
        str(gt_block.get("parent_node_urn") or "").strip()
        or cfg.get("domain_urn")
        or _FALLBACK_GLOSSARY_PARENT_NODE_URN
    )
    terms = gt_block["terms"] if isinstance(gt_block["terms"], list) else []
    created_urns: list[str] = []

    for term in terms:
        if not isinstance(term, dict):
            continue
        term_id = str(term.get("id") or "").strip()
        label = str(term.get("name") or term_id)
        if not term_id:
            _fail("curated.glossaryTerm", f"term entry missing 'id': {term}")
            continue

        term_urn = _glossary_term_urn(term_id)

        if _term_exists(term_id):
            print(f"  \u2192 {label}: already exists — skipping create")
        else:
            payload: dict[str, Any] = {
                "id": term_id,
                "name": label,
                "description": str(term.get("description") or ""),
            }
            if parent_node:
                payload["parentNode"] = parent_node

            data = _post(_CREATE_GLOSSARY_TERM, {"input": payload})
            if data and data.get("createGlossaryTerm"):
                _ok(f"{label} ({data['createGlossaryTerm']})")
            else:
                _fail(label, f"unexpected response: {data}")
                continue

        rt = term.get("related_terms") or []
        if rt:
            _push_term_related_terms(term_urn, rt)

        created_urns.append(term_urn)

    if not created_urns:
        return

    dp_u = _data_product_urn(str(cfg["data_product_id"]))
    terms_data = _post(
        _BATCH_ADD_TERMS,
        {
            "input": {
                "termUrns": created_urns,
                "resources": [{"resourceUrn": dp_u}],
            }
        },
    )
    if terms_data and terms_data.get("batchAddTerms"):
        _ok(f"Attached {len(created_urns)} glossary term(s) to DataProduct")
    else:
        _fail("curated.batchAddTerms", f"unexpected response: {terms_data}")


def _curated_extra_query_discovery_urls(cfg: dict[str, Any]) -> list[str]:
    assert isinstance(cfg.get("golden_query"), dict)
    keeper = str(cfg["golden_query"]["stable_urn"])
    name_frag = str(cfg["golden_query"]["name"])
    blob = _post(_SEARCH_QUERIES, {"frag": name_frag})
    if blob is None:
        return []
    urls: list[str] = []
    rs = ((blob.get("search") or {}).get("searchResults")) or []
    ui_base = DATAHUB_UI_ORIGIN.rstrip("/")
    for row in rs:
        ent_u = (((row.get("entity") or {}).get("urn")) or "").strip()
        if not ent_u.startswith("urn:li:query:"):
            continue
        if ent_u == keeper:
            continue
        urls.append(f"{ui_base}/query/{ent_u}")
    return sorted(set(urls))


def curated_purge_discovery_links(cfg: dict[str, Any]) -> None:
    print("\n[4/7] Purge golden-query deep links...")
    keeper_u = str(cfg["golden_query"]["stable_urn"])
    dp_u = _data_product_urn(str(cfg["data_product_id"]))
    ui_base = DATAHUB_UI_ORIGIN.rstrip("/")
    targets = {f"{ui_base}/query/{keeper_u}"}
    targets.update(_curated_extra_query_discovery_urls(cfg))
    yaml_extra = cfg.get("extra_discovery_link_urls_remove") or []
    if isinstance(yaml_extra, list):
        targets.update(str(u) for u in yaml_extra)
    for url in sorted(targets):
        root = _graphql_root(
            _REMOVE_LINK,
            {"input": {"linkUrl": url, "resourceUrn": dp_u}},
        )
        errs = (root or {}).get("errors") or []
        if errs:
            treat_ok = any(
                needle in ((err_item.get("message") or "").lower())
                for err_item in errs
                for needle in ("not found", "does not exist", "unknown")
            )
            if not treat_ok:
                _fail(
                    f"removeLink curated [{url}]",
                    json.dumps(root, default=str),
                )
        else:
            _ok("Removed golden-query Summary URL (if present)")


def curated_push_create_query(cfg: dict[str, Any]) -> None:
    print("\n[5/7] Golden Query entity...")
    gq = cfg["golden_query"]
    assert isinstance(gq, dict)
    name = str(gq["name"])
    desc_text = str(gq.get("description") or name).strip()
    sql_txt = str(gq.get("sql") or "").strip()
    subj = _curated_dataset_subject_urns(cfg)
    root = _graphql_root(
        _CREATE_QUERY,
        {
            "input": {
                "properties": {
                    "name": name,
                    "description": desc_text or name,
                    "statement": {"value": sql_txt, "language": "SQL"},
                },
                "subjects": [{"datasetUrn": u} for u in sorted(subj)],
            },
        },
    )
    errs = (root or {}).get("errors") or []
    data_n = (root or {}).get("data") if not errs else {}
    if not errs:
        cq_blob = data_n.get("createQuery") or {}
        urn_c = cq_blob.get("urn") if isinstance(cq_blob, dict) else None
        if urn_c:
            _ok(f"Created Query {urn_c}")
            return
    if errs and _errors_indicate_already_exists(errs):
        print("  -> createQuery duplicate — using YAML golden_query.stable_urn")
        return
    _fail("curated.createQuery", json.dumps({"errors": errs, "data": data_n}))


def curated_push_sidebar_struct_props(cfg: dict[str, Any]) -> None:
    print("\n[6/7] Sidebar structured property...")
    spec_sp = cfg.get("structured_property")
    if not isinstance(spec_sp, dict) or not spec_sp.get("qualified_name"):
        raise SystemExit("`structured_property.qualified_name` is required")

    golden = cfg["golden_query"]
    assert isinstance(golden, dict)
    pid = str(cfg["data_product_id"])
    dp_u = _data_product_urn(pid)
    q_name = str(spec_sp["qualified_name"])
    keeper_q = str(golden["stable_urn"])

    raw_legacy = spec_sp.get("legacy_qualified_names_to_drop") or []
    legacy_skip = frozenset(
        structured_property_urn(str(q_str).strip())
        for q_str in (raw_legacy if isinstance(raw_legacy, list) else [])
        if str(q_str).strip()
    )

    ensure_dp_golden_struct_property(q_name)
    merged_blob = _merged_dp_structured_props(
        dp_u,
        golden_sp_qname=q_name,
        golden_query_urn_val=keeper_q,
        legacy_skip_urns=legacy_skip,
    )
    if merged_blob is None:
        _fail(
            "curated.upsertStructuredProperties",
            "merge aborted (see stderr)",
        )
        return
    upl = _post(
        _UPSERT_STRUCTURED_PROPERTIES,
        {
            "input": {
                "assetUrn": dp_u,
                "structuredPropertyInputParams": merged_blob,
            },
        },
    )
    if upl is None or upl.get("upsertStructuredProperties") is None:
        _fail("curated.upsertStructuredProperties", repr(upl))
        return
    _ok(f"Upserted {len(merged_blob)} structured-prop bucket(s)")


def curated_refresh_dataset_assets(cfg: dict[str, Any]) -> None:
    print("\n[7/7] Re-affirm dataset-only memberships...")
    urns_r = _curated_data_product_asset_urns(cfg)
    ref = _post(
        _SET_DATA_PRODUCT_ASSETS,
        {
            "input": {
                "dataProductUrn": _data_product_urn(str(cfg["data_product_id"])),
                "resourceUrns": urns_r,
            },
        },
    )
    if ref is None:
        _fail("curated.datasets.refresh", "batchSet returned None")
        return
    _ok(f"Pinned {len(urns_r)} datasets")


def curated_push_dataset_descriptions(cfg: dict[str, Any]) -> None:
    """Push per-dataset descriptions declared inline in the YAML ``datasets`` list."""
    rows = [
        r
        for r in (cfg.get("datasets") or [])
        if isinstance(r, dict) and r.get("description")
    ]
    if not rows:
        return
    print("\n[1b] Dataset descriptions...")
    for row in rows:
        schema = str(row.get("schema") or "")
        table = str(row.get("table") or "")
        desc = str(row["description"]).strip()
        urn = _urn(schema, table)
        label = f"{schema}.{table}"
        data = _post(_UPDATE_DATASET_DESCRIPTION, {"urn": urn, "description": desc})
        if data and data.get("updateDataset"):
            _ok(label)
        else:
            _fail(label, f"mutation returned unexpected response: {data}")


def curated_push_field_descriptions(cfg: dict[str, Any]) -> None:
    """Push per-field descriptions declared inline in the YAML ``datasets`` list."""
    rows = [
        r
        for r in (cfg.get("datasets") or [])
        if isinstance(r, dict) and isinstance(r.get("fields"), dict)
    ]
    if not rows:
        return
    print("\n[1c] Schema field descriptions...")
    for row in rows:
        schema = str(row.get("schema") or "")
        table = str(row.get("table") or "")
        urn = _urn(schema, table)
        for field_path, description in row["fields"].items():
            label = f"{schema}.{table}.{field_path}"
            data = _post(
                _UPDATE_FIELD_DESCRIPTION,
                {
                    "description": str(description),
                    "resourceUrn": urn,
                    "fieldPath": str(field_path),
                },
            )
            if data is not None and data.get("updateDescription") is not False:
                _ok(label)
            else:
                _fail(label, f"unexpected response: {data}")


def run_data_product_curated_entity(spec: dict[str, Any]) -> None:
    curated_push_assets(spec)
    curated_push_dataset_descriptions(spec)
    curated_push_field_descriptions(spec)
    curated_push_documentation_link(spec)
    curated_push_glossary_terms(spec)
    curated_purge_discovery_links(spec)
    curated_push_create_query(spec)
    curated_push_sidebar_struct_props(spec)
    curated_refresh_dataset_assets(spec)


def _pipeline_reset_errors() -> None:
    global _errors
    _errors = []


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    if not GRAPHQL_URL:
        print(
            "ERROR: DATAHUB_GRAPHQL_URL is not set.\n"
            "  export DATAHUB_GRAPHQL_URL=https://<datahub-host>/api/graphql\n"
            "  export DATAHUB_TOKEN=<personal-access-token>",
            file=sys.stderr,
        )
        sys.exit(1)

    parser = argparse.ArgumentParser(
        description="Push DataHub curated context from YAML (spec_version: 1).",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG_PATH,
        help=(
            "Path to *.datahub.yaml "
            "(default: datahub_entities/collections-recovery.datahub.yaml beside this script)"
        ),
    )
    ns = parser.parse_args()
    path = ns.config.resolve()

    print(f"DataHub target  : {GRAPHQL_URL}")
    print(f"Auth token       : {'set' if TOKEN else 'NOT SET (mutations may fail)'}")
    print(f"Config file      : {path}")

    if not path.exists():
        print(f"Missing config file: {path}", file=sys.stderr)
        sys.exit(1)

    bundle = load_yaml_spec(path)
    _ensure_spec_supported(bundle, path)
    kind_sel = bundle.get("kind")

    print(f"preset.kind      : {kind_sel}")

    _pipeline_reset_errors()

    try:
        if kind_sel == KIND_DATA_PRODUCT_CURATED_ENTITY:
            run_data_product_curated_entity(bundle)
        else:
            raise SystemExit(
                f"{path}: unsupported kind {kind_sel!r} "
                f"(expected '{KIND_DATA_PRODUCT_CURATED_ENTITY}')"
            )

        print("\n" + "=" * 60)
        if _errors:
            print(f"DONE with {len(_errors)} error(s):")
            for detail in _errors:
                print(f"  {detail}")
            sys.exit(1)
        print("All mutations succeeded.")
    except SystemExit:
        raise
    except BaseException as exc:  # pragma: no cover
        print(f"ABORTED: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
